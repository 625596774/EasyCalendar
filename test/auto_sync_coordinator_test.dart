import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/todo/todo_repository.dart';
import 'package:zrk_calendar/services/sync/auto_sync_coordinator.dart';
import 'package:zrk_calendar/services/sync/sync_service.dart';
import 'package:zrk_calendar/services/sync/sync_state.dart';

void main() {
  const debounceDelay = Duration(milliseconds: 30);
  const debounceWait = Duration(milliseconds: 90);

  test('本地修改后会 debounce 自动同步', () async {
    var hasPending = true;
    final fakeSyncService = _FakeSyncService.signedIn();
    final coordinator = await _createCoordinator(
      syncService: fakeSyncService,
      pendingSyncItemsChecker: () async => hasPending,
      debounceDelay: debounceDelay,
    );
    addTearDown(coordinator.dispose);

    await coordinator.notifyLocalChange();
    expect(fakeSyncService.syncCallCount, 0);

    await Future<void>.delayed(debounceWait);
    expect(fakeSyncService.syncCallCount, 1);

    hasPending = false;
  });

  test('多次连续本地修改只触发一次实际同步', () async {
    final fakeSyncService = _FakeSyncService.signedIn();
    final coordinator = await _createCoordinator(
      syncService: fakeSyncService,
      pendingSyncItemsChecker: () async => true,
      debounceDelay: debounceDelay,
    );
    addTearDown(coordinator.dispose);

    await coordinator.notifyLocalChange();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await coordinator.notifyLocalChange();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await coordinator.notifyLocalChange();

    await Future<void>.delayed(debounceWait);
    expect(fakeSyncService.syncCallCount, 1);
  });

  test('未登录时不会自动同步，也不会报错', () async {
    final fakeSyncService = _FakeSyncService.signedOut();
    final coordinator = await _createCoordinator(
      syncService: fakeSyncService,
      pendingSyncItemsChecker: () async => true,
      debounceDelay: debounceDelay,
    );
    addTearDown(coordinator.dispose);

    await coordinator.notifyLocalChange();
    await coordinator.handleAppResumed();
    await Future<void>.delayed(debounceWait);

    expect(fakeSyncService.syncCallCount, 0);
  });

  test('手动同步立即执行，并取消 debounce 自动同步', () async {
    final fakeSyncService = _FakeSyncService.signedIn();
    final coordinator = await _createCoordinator(
      syncService: fakeSyncService,
      pendingSyncItemsChecker: () async => true,
      debounceDelay: debounceDelay,
    );
    addTearDown(coordinator.dispose);

    await coordinator.notifyLocalChange();
    await coordinator.syncNow();
    expect(fakeSyncService.syncCallCount, 1);

    await Future<void>.delayed(debounceWait);
    expect(fakeSyncService.syncCallCount, 1);
  });

  test('同步中不会并发执行第二个同步', () async {
    final releaseSync = Completer<void>();
    final fakeSyncService = _FakeSyncService.signedIn(syncDelay: releaseSync);
    final coordinator = await _createCoordinator(
      syncService: fakeSyncService,
      pendingSyncItemsChecker: () async => true,
      debounceDelay: debounceDelay,
    );
    addTearDown(coordinator.dispose);

    final firstSync = coordinator.syncNow();
    await fakeSyncService.syncStarted.future;
    final secondSync = coordinator.syncNow();

    expect(fakeSyncService.syncCallCount, 1);
    expect(fakeSyncService.maxConcurrentSyncs, 1);

    releaseSync.complete();
    await Future.wait([firstSync, secondSync]);
    expect(fakeSyncService.syncCallCount, 1);
  });

  test('App resumed 时如果有 pending/failed 数据会触发自动同步', () async {
    final fakeSyncService = _FakeSyncService.signedIn();
    final coordinator = await _createCoordinator(
      syncService: fakeSyncService,
      pendingSyncItemsChecker: () async => true,
      debounceDelay: debounceDelay,
    );
    addTearDown(coordinator.dispose);

    await coordinator.handleAppResumed();

    expect(fakeSyncService.syncCallCount, 1);
  });

  test('App resumed 时如果没有 pending/failed 数据不触发自动同步', () async {
    final fakeSyncService = _FakeSyncService.signedIn();
    final coordinator = await _createCoordinator(
      syncService: fakeSyncService,
      pendingSyncItemsChecker: () async => false,
      debounceDelay: debounceDelay,
    );
    addTearDown(coordinator.dispose);

    await coordinator.handleAppResumed();

    expect(fakeSyncService.syncCallCount, 0);
  });

  test('同步失败时不会丢本地数据，状态能显示 failed', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final todoRepository = TodoRepository(database);
    addTearDown(database.close);

    final date = DateTime(2026, 6, 10);
    await todoRepository.addTodo(title: '离线保留', date: date);

    final fakeSyncService = _FakeSyncService.signedIn(shouldFail: true);
    final coordinator = await _createCoordinator(
      syncService: fakeSyncService,
      pendingSyncItemsChecker: todoRepository.hasPendingTodosIncludingDeleted,
      debounceDelay: debounceDelay,
    );
    addTearDown(coordinator.dispose);
    final states = <SyncState>[];
    final subscription = coordinator.watchState().listen(states.add);
    addTearDown(subscription.cancel);

    await coordinator.syncNow();
    await Future<void>.delayed(Duration.zero);

    final todos = await todoRepository.getTodosForDate(date);
    expect(todos, hasLength(1));
    expect(todos.single.title, '离线保留');
    expect(
      states.map((state) => state.status),
      contains(SyncStateStatus.failed),
    );
  });
}

Future<AutoSyncCoordinator> _createCoordinator({
  required SyncService syncService,
  required PendingSyncItemsChecker pendingSyncItemsChecker,
  required Duration debounceDelay,
}) async {
  final coordinator = AutoSyncCoordinator(
    syncService: syncService,
    pendingSyncItemsChecker: pendingSyncItemsChecker,
    debounceDelay: debounceDelay,
  );
  await coordinator.initialize();
  await Future<void>.delayed(Duration.zero);
  return coordinator;
}

class _FakeSyncService implements SyncService {
  _FakeSyncService.signedIn({this.shouldFail = false, this.syncDelay})
    : _state = const SyncState(
        status: SyncStateStatus.success,
        message: '已同步。',
        currentUserEmail: 'tester@example.com',
      );

  _FakeSyncService.signedOut()
    : shouldFail = false,
      syncDelay = null,
      _state = const SyncState(
        status: SyncStateStatus.unauthenticated,
        message: '未登录。',
      );

  final bool shouldFail;
  final Completer<void>? syncDelay;
  final StreamController<SyncState> _controller =
      StreamController<SyncState>.broadcast();
  final Completer<void> syncStarted = Completer<void>();

  SyncState _state;
  int syncCallCount = 0;
  int _concurrentSyncs = 0;
  int maxConcurrentSyncs = 0;

  @override
  Stream<SyncState> watchState() async* {
    yield _state;
    yield* _controller.stream;
  }

  @override
  Future<void> initialize() async {
    _emit(_state);
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _emit(
      SyncState(
        status: SyncStateStatus.success,
        message: '已登录。',
        currentUserEmail: email,
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _emit(
      const SyncState(status: SyncStateStatus.unauthenticated, message: '已退出。'),
    );
  }

  @override
  Future<void> syncNow() async {
    syncCallCount += 1;
    _concurrentSyncs += 1;
    if (_concurrentSyncs > maxConcurrentSyncs) {
      maxConcurrentSyncs = _concurrentSyncs;
    }
    if (!syncStarted.isCompleted) {
      syncStarted.complete();
    }
    _emit(
      SyncState(
        status: SyncStateStatus.syncing,
        message: '同步中。',
        currentUserEmail: _state.currentUserEmail,
        lastSyncedAt: _state.lastSyncedAt,
      ),
    );
    try {
      await syncDelay?.future;
      if (shouldFail) {
        _emit(
          SyncState(
            status: SyncStateStatus.failed,
            message: '同步失败。',
            currentUserEmail: _state.currentUserEmail,
            lastSyncedAt: _state.lastSyncedAt,
          ),
        );
        return;
      }
      _emit(
        SyncState(
          status: SyncStateStatus.success,
          message: '已同步。',
          currentUserEmail: _state.currentUserEmail,
          lastSyncedAt: DateTime(2026, 6, 10).toUtc(),
        ),
      );
    } finally {
      _concurrentSyncs -= 1;
    }
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void _emit(SyncState state) {
    _state = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}
