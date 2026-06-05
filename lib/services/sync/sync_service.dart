import 'sync_state.dart';

abstract class SyncService {
  Stream<SyncState> watchState();

  Future<void> initialize();

  Future<void> signIn({required String email, required String password});

  Future<void> signOut();

  Future<void> syncNow();

  Future<void> dispose();
}
