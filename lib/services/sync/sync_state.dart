enum SyncStateStatus { disabled, idle, syncing, success, failed }

class SyncState {
  const SyncState({required this.status, this.message, this.lastSyncedAt});

  final SyncStateStatus status;
  final String? message;
  final DateTime? lastSyncedAt;

  SyncState copyWith({
    SyncStateStatus? status,
    String? message,
    DateTime? lastSyncedAt,
  }) {
    return SyncState(
      status: status ?? this.status,
      message: message ?? this.message,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}
