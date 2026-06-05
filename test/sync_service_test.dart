import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/todo/todo_repository.dart';
import 'package:zrk_calendar/services/sync/noop_sync_service.dart';
import 'package:zrk_calendar/services/sync/sync_state.dart';

void main() {
  test('NoopSyncService.syncNow 不访问网络且不会破坏本地数据', () async {
    final database = AppDatabase(NativeDatabase.memory());
    final todoRepository = TodoRepository(database);
    final syncService = NoopSyncService();
    final states = <SyncState>[];
    final subscription = syncService.watchState().listen(states.add);
    addTearDown(() async {
      await subscription.cancel();
      await syncService.dispose();
      await database.close();
    });

    final date = DateTime(2026, 6, 5);
    await todoRepository.addTodo(title: '保留本地数据', date: date);

    await syncService.initialize();
    await syncService.syncNow();
    await Future<void>.delayed(Duration.zero);

    final todos = await todoRepository.getTodosForDate(date);
    expect(todos, hasLength(1));
    expect(
      states.map((state) => state.status),
      contains(SyncStateStatus.success),
    );
  });
}
