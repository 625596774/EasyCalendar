import 'dart:async';

import 'sync_service.dart';
import 'sync_state.dart';

class NoopSyncService implements SyncService {
  NoopSyncService({String? message})
    : _state = SyncState(
        status: SyncStateStatus.disabled,
        message: message ?? '当前版本尚未启用云同步。',
      );

  final StreamController<SyncState> _controller =
      StreamController<SyncState>.broadcast();

  SyncState _state;

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
      const SyncState(
        status: SyncStateStatus.disabled,
        message: '当前版本尚未接入账号登录。',
      ),
    );
  }

  @override
  Future<void> signOut() async {
    _emit(
      const SyncState(
        status: SyncStateStatus.disabled,
        message: '当前版本尚未接入账号登录。',
      ),
    );
  }

  @override
  Future<void> syncNow() async {
    _emit(
      SyncState(
        status: SyncStateStatus.success,
        message: '本地模式，无需同步。',
        lastSyncedAt: DateTime.now(),
      ),
    );
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
