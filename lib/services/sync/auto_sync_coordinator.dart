import 'dart:async';

import 'sync_service.dart';
import 'sync_state.dart';

typedef PendingSyncItemsChecker = Future<bool> Function();

class AutoSyncCoordinator implements SyncService {
  AutoSyncCoordinator({
    required this.syncService,
    required this.pendingSyncItemsChecker,
    this.debounceDelay = const Duration(seconds: 4),
  });

  final SyncService syncService;
  final PendingSyncItemsChecker pendingSyncItemsChecker;
  final Duration debounceDelay;
  final StreamController<SyncState> _controller =
      StreamController<SyncState>.broadcast();

  SyncState _state = const SyncState(
    status: SyncStateStatus.unauthenticated,
    message: '云同步未登录。',
  );
  StreamSubscription<SyncState>? _stateSubscription;
  Timer? _debounceTimer;
  Future<void>? _syncInFlight;
  bool _syncAgainAfterCurrent = false;
  bool _delegateIsSyncing = false;
  bool _isDisposed = false;

  @override
  Stream<SyncState> watchState() async* {
    _ensureStateSubscription();
    yield _state;
    yield* _controller.stream;
  }

  @override
  Future<void> initialize() async {
    _ensureStateSubscription();
    await syncService.initialize();
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    _cancelDebounce();
    await syncService.signIn(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    _cancelDebounce();
    _syncAgainAfterCurrent = false;
    await syncService.signOut();
  }

  @override
  Future<void> syncNow() {
    _cancelDebounce();
    _syncAgainAfterCurrent = false;
    return _runSyncNow();
  }

  Future<void> notifyLocalChange() async {
    if (!_isLoggedIn || _isDisposed) {
      return;
    }
    if (_syncInFlight != null || _delegateIsSyncing) {
      _syncAgainAfterCurrent = true;
      return;
    }
    _emit(
      SyncState(
        status: SyncStateStatus.pending,
        message: '有本地更改等待同步。',
        lastSyncedAt: _state.lastSyncedAt,
        currentUserEmail: _state.currentUserEmail,
      ),
    );
    _cancelDebounce();
    _debounceTimer = Timer(debounceDelay, () {
      unawaited(_syncIfPending());
    });
  }

  Future<void> handleAppResumed() {
    if (!_isLoggedIn || _isDisposed) {
      return Future<void>.value();
    }
    return _syncIfPending();
  }

  Future<bool> hasPendingSyncItems() {
    return pendingSyncItemsChecker();
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    _cancelDebounce();
    _syncAgainAfterCurrent = false;
    await _stateSubscription?.cancel();
    await syncService.dispose();
    await _controller.close();
  }

  Future<void> _syncIfPending() async {
    if (!_isLoggedIn || _isDisposed) {
      return;
    }
    if (_syncInFlight != null || _delegateIsSyncing) {
      _syncAgainAfterCurrent = true;
      await _syncInFlight;
      return;
    }
    bool hasPending;
    try {
      hasPending = await pendingSyncItemsChecker();
    } on Object {
      _emit(
        SyncState(
          status: SyncStateStatus.failed,
          message: '检查待同步数据失败，本地数据已保留。',
          lastSyncedAt: _state.lastSyncedAt,
          currentUserEmail: _state.currentUserEmail,
        ),
      );
      return;
    }
    if (!hasPending) {
      if (_state.status == SyncStateStatus.pending) {
        _emit(
          SyncState(
            status: SyncStateStatus.success,
            message: '已同步。',
            lastSyncedAt: _state.lastSyncedAt,
            currentUserEmail: _state.currentUserEmail,
          ),
        );
      }
      return;
    }
    await _runSyncNow();
  }

  Future<void> _runSyncNow() {
    final inFlight = _syncInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    if (_delegateIsSyncing) {
      return Future<void>.value();
    }

    final future = _performSyncNow();
    _syncInFlight = future;
    return future;
  }

  Future<void> _performSyncNow() async {
    try {
      await syncService.syncNow();
    } finally {
      _syncInFlight = null;
      if (_syncAgainAfterCurrent && !_isDisposed) {
        _syncAgainAfterCurrent = false;
        unawaited(_syncIfPending());
      }
    }
  }

  void _ensureStateSubscription() {
    _stateSubscription ??= syncService.watchState().listen(_handleSyncState);
  }

  void _handleSyncState(SyncState state) {
    final wasDelegateSyncing = _delegateIsSyncing;
    _delegateIsSyncing = state.status == SyncStateStatus.syncing;
    if (state.status == SyncStateStatus.unauthenticated ||
        state.status == SyncStateStatus.disabled) {
      _cancelDebounce();
      _syncAgainAfterCurrent = false;
    }
    _emit(state);
    if (wasDelegateSyncing &&
        !_delegateIsSyncing &&
        _syncInFlight == null &&
        _syncAgainAfterCurrent &&
        !_isDisposed) {
      _syncAgainAfterCurrent = false;
      unawaited(_syncIfPending());
    }
  }

  void _cancelDebounce() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }

  bool get _isLoggedIn {
    return _state.currentUserEmail != null &&
        _state.status != SyncStateStatus.disabled &&
        _state.status != SyncStateStatus.unauthenticated;
  }

  void _emit(SyncState state) {
    _state = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }
}
