import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/recurring_event/recurring_event_repository.dart';
import '../../features/todo/todo_repository.dart';
import 'sync_models.dart';
import 'sync_service.dart';
import 'sync_state.dart';

class SupabaseSyncService implements SyncService {
  SupabaseSyncService({
    required SupabaseClient client,
    required TodoRepository todoRepository,
    required RecurringEventRepository recurringEventRepository,
  }) : this._(
         client: client,
         todoRepository: todoRepository,
         recurringEventRepository: recurringEventRepository,
       );

  SupabaseSyncService._({
    required this._client,
    required this._todoRepository,
    required this._recurringEventRepository,
  });

  final SupabaseClient _client;
  final TodoRepository _todoRepository;
  final RecurringEventRepository _recurringEventRepository;
  final StreamController<SyncState> _controller =
      StreamController<SyncState>.broadcast();

  SyncState _state = const SyncState(
    status: SyncStateStatus.unauthenticated,
    message: '云同步未登录。',
  );
  bool _isSyncing = false;

  @override
  Stream<SyncState> watchState() async* {
    yield _state;
    yield* _controller.stream;
  }

  @override
  Future<void> initialize() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      _emit(
        const SyncState(
          status: SyncStateStatus.unauthenticated,
          message: '云同步未登录。',
        ),
      );
      return;
    }
    _emit(
      SyncState(
        status: SyncStateStatus.idle,
        message: '已登录，准备同步。',
        currentUserEmail: user.email,
      ),
    );
    unawaited(syncNow());
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _emit(const SyncState(status: SyncStateStatus.syncing, message: '正在登录...'));
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      final user = _client.auth.currentUser;
      if (user == null) {
        _emit(
          const SyncState(
            status: SyncStateStatus.failed,
            message: '登录失败，请检查邮箱和密码。',
          ),
        );
        return;
      }
      _emit(
        SyncState(
          status: SyncStateStatus.idle,
          message: '登录成功。',
          currentUserEmail: user.email,
        ),
      );
      await syncNow();
    } on AuthException catch (error) {
      _emit(
        SyncState(
          status: SyncStateStatus.failed,
          message: _readableAuthError(error.message),
        ),
      );
    } on Object {
      _emit(
        const SyncState(status: SyncStateStatus.failed, message: '登录失败，请稍后重试。'),
      );
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } finally {
      _emit(
        const SyncState(
          status: SyncStateStatus.unauthenticated,
          message: '已退出登录，本地数据仍可继续使用。',
        ),
      );
    }
  }

  @override
  Future<void> syncNow() async {
    if (_isSyncing) {
      return;
    }
    final user = _client.auth.currentUser;
    if (user == null) {
      _emit(
        const SyncState(
          status: SyncStateStatus.unauthenticated,
          message: '请先登录后再同步。',
        ),
      );
      return;
    }

    _isSyncing = true;
    _emit(
      SyncState(
        status: SyncStateStatus.syncing,
        message: '正在同步...',
        currentUserEmail: user.email,
        lastSyncedAt: _state.lastSyncedAt,
      ),
    );
    final syncedAt = DateTime.now().toUtc();
    try {
      await _syncTodos(user.id, syncedAt);
      await _syncRecurringEvents(user.id, syncedAt);
      _emit(
        SyncState(
          status: SyncStateStatus.success,
          message: '同步完成。',
          lastSyncedAt: syncedAt,
          currentUserEmail: user.email,
        ),
      );
    } on Object catch (error) {
      await _markPendingRecordsFailed();
      _emit(
        SyncState(
          status: SyncStateStatus.failed,
          message:
              '同步失败：${safeSyncErrorDetails(error)}。'
              '本地数据已保留，可稍后重试。',
          lastSyncedAt: _state.lastSyncedAt,
          currentUserEmail: user.email,
        ),
      );
    } finally {
      _isSyncing = false;
    }
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  Future<void> _syncTodos(String userId, DateTime syncedAt) async {
    await _todoRepository.repairEmptyPendingTodoTitlesForSync();
    final pending = await _todoRepository.getPendingTodosIncludingDeleted();
    for (final todo in pending) {
      final record = TodoSyncRecord.fromTodoItem(todo);
      final remote = await _fetchRemoteTodo(userId: userId, id: record.id);
      if (remote != null &&
          chooseUpdatedAtWinner(
                localUpdatedAt: record.updatedAt,
                remoteUpdatedAt: remote.updatedAt,
              ) ==
              SyncMergeDecision.useRemote) {
        await _todoRepository.upsertFromSync(remote, syncedAt: syncedAt);
        continue;
      }
      await _client
          .from('todo_items')
          .upsert(record.toSupabasePayload(userId: userId), onConflict: 'id');
      await _todoRepository.markTodoSynced(todo.id, syncedAt);
    }

    final remoteRows = _rows(
      await _client.from('todo_items').select().eq('user_id', userId),
    );
    for (final row in remoteRows) {
      final remote = TodoSyncRecord.fromSupabaseRow(row);
      final local = await _todoRepository.getTodoByIdIncludingDeleted(
        remote.id,
      );
      if (local == null) {
        await _todoRepository.upsertFromSync(remote, syncedAt: syncedAt);
        continue;
      }

      final decision = chooseUpdatedAtWinner(
        localUpdatedAt: local.updatedAt,
        remoteUpdatedAt: remote.updatedAt,
      );
      if (decision == SyncMergeDecision.useRemote) {
        await _todoRepository.upsertFromSync(remote, syncedAt: syncedAt);
      } else {
        final localRecord = TodoSyncRecord.fromTodoItem(local);
        await _client
            .from('todo_items')
            .upsert(
              localRecord.toSupabasePayload(userId: userId),
              onConflict: 'id',
            );
        await _todoRepository.markTodoSynced(local.id, syncedAt);
      }
    }
  }

  Future<void> _syncRecurringEvents(String userId, DateTime syncedAt) async {
    final pending = await _recurringEventRepository
        .getPendingEventsIncludingDeleted();
    for (final event in pending) {
      final record = RecurringEventSyncRecord.fromRecurringEvent(event);
      final remote = await _fetchRemoteRecurringEvent(
        userId: userId,
        id: record.id,
      );
      if (remote != null &&
          chooseUpdatedAtWinner(
                localUpdatedAt: record.updatedAt,
                remoteUpdatedAt: remote.updatedAt,
              ) ==
              SyncMergeDecision.useRemote) {
        await _recurringEventRepository.upsertFromSync(
          remote,
          syncedAt: syncedAt,
        );
        continue;
      }
      await _client
          .from('recurring_events')
          .upsert(record.toSupabasePayload(userId: userId), onConflict: 'id');
      await _recurringEventRepository.markEventSynced(event.id, syncedAt);
    }

    final remoteRows = _rows(
      await _client.from('recurring_events').select().eq('user_id', userId),
    );
    for (final row in remoteRows) {
      final remote = RecurringEventSyncRecord.fromSupabaseRow(row);
      final local = await _recurringEventRepository
          .getEventByIdIncludingDeleted(remote.id);
      if (local == null) {
        await _recurringEventRepository.upsertFromSync(
          remote,
          syncedAt: syncedAt,
        );
        continue;
      }

      final decision = chooseUpdatedAtWinner(
        localUpdatedAt: local.updatedAt,
        remoteUpdatedAt: remote.updatedAt,
      );
      if (decision == SyncMergeDecision.useRemote) {
        await _recurringEventRepository.upsertFromSync(
          remote,
          syncedAt: syncedAt,
        );
      } else {
        final localRecord = RecurringEventSyncRecord.fromRecurringEvent(local);
        await _client
            .from('recurring_events')
            .upsert(
              localRecord.toSupabasePayload(userId: userId),
              onConflict: 'id',
            );
        await _recurringEventRepository.markEventSynced(local.id, syncedAt);
      }
    }
  }

  Future<void> _markPendingRecordsFailed() async {
    final todos = await _todoRepository.getPendingTodosIncludingDeleted();
    for (final todo in todos) {
      await _todoRepository.markTodoSyncFailed(todo.id);
    }
    final events = await _recurringEventRepository
        .getPendingEventsIncludingDeleted();
    for (final event in events) {
      await _recurringEventRepository.markEventSyncFailed(event.id);
    }
  }

  Future<TodoSyncRecord?> _fetchRemoteTodo({
    required String userId,
    required String id,
  }) async {
    final rows = _rows(
      await _client
          .from('todo_items')
          .select()
          .eq('user_id', userId)
          .eq('id', id)
          .limit(1),
    );
    if (rows.isEmpty) {
      return null;
    }
    return TodoSyncRecord.fromSupabaseRow(rows.single);
  }

  Future<RecurringEventSyncRecord?> _fetchRemoteRecurringEvent({
    required String userId,
    required String id,
  }) async {
    final rows = _rows(
      await _client
          .from('recurring_events')
          .select()
          .eq('user_id', userId)
          .eq('id', id)
          .limit(1),
    );
    if (rows.isEmpty) {
      return null;
    }
    return RecurringEventSyncRecord.fromSupabaseRow(rows.single);
  }

  List<Map<String, dynamic>> _rows(Object data) {
    if (data is! List) {
      return const [];
    }
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _readableAuthError(String message) {
    final normalized = message.toLowerCase();
    if (normalized.contains('invalid') || normalized.contains('credentials')) {
      return '登录失败，请检查邮箱和密码。';
    }
    return '登录失败：$message';
  }

  void _emit(SyncState state) {
    _state = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}

String safeSyncErrorDetails(Object error) {
  if (error is PostgrestException) {
    return _joinErrorParts([
      'PostgrestException',
      error.code,
      _safeErrorText(error.message),
    ]);
  }
  if (error is AuthException) {
    return _joinErrorParts(['AuthException', _safeErrorText(error.message)]);
  }
  if (error is SocketException) {
    return _joinErrorParts(['SocketException', _safeErrorText(error.message)]);
  }
  if (error is FormatException) {
    return _joinErrorParts(['FormatException', _safeErrorText(error.message)]);
  }
  return _safeErrorText(error.runtimeType.toString()) ?? 'unknown';
}

String _joinErrorParts(Iterable<Object?> parts) {
  return parts
      .map((part) => _safeErrorText(part))
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(' / ');
}

String? _safeErrorText(Object? value) {
  final raw = value?.toString().trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  var text = raw
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'https?://\S+'), '[url]')
      .replaceAll(RegExp(r'\b[\w.%+-]+@[\w.-]+\.[A-Za-z]{2,}\b'), '[email]')
      .replaceAll(
        RegExp(
          r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
          r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
        ),
        '[id]',
      )
      .replaceAll(RegExp(r'\b[A-Za-z0-9_-]{32,}\b'), '[redacted]');
  text = text.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  if (text.length <= 180) {
    return text;
  }
  return '${text.substring(0, 177)}...';
}
