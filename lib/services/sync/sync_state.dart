enum SyncStateStatus {
  disabled,
  unauthenticated,
  idle,
  syncing,
  success,
  failed,
}

class SyncState {
  const SyncState({
    required this.status,
    this.message,
    this.lastSyncedAt,
    this.currentUserEmail,
  });

  final SyncStateStatus status;
  final String? message;
  final DateTime? lastSyncedAt;
  final String? currentUserEmail;

  SyncState copyWith({
    SyncStateStatus? status,
    String? message,
    DateTime? lastSyncedAt,
    String? currentUserEmail,
  }) {
    return SyncState(
      status: status ?? this.status,
      message: message ?? this.message,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      currentUserEmail: currentUserEmail ?? this.currentUserEmail,
    );
  }
}
