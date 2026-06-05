import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_models.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_repository.dart';
import 'package:zrk_calendar/features/todo/todo_repository.dart';

void main() {
  late AppDatabase database;
  late TodoRepository todoRepository;
  late RecurringEventRepository recurringEventRepository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    todoRepository = TodoRepository(database);
    recurringEventRepository = RecurringEventRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('待办生成 UUID，更新标记 pending，删除为软删除', () async {
    final date = DateTime(2026, 6, 3);
    final id = await todoRepository.addTodo(title: '写第一版日历', date: date);
    expect(id, matches(_uuidPattern));

    var todos = await todoRepository.getTodosForDate(date);
    expect(todos, hasLength(1));
    expect(todos.single.id, id);
    expect(todos.single.isCompleted, isFalse);
    expect(todos.single.deletedAt, isNull);
    expect(todos.single.syncStatus, TodoRepository.pendingSyncStatus);
    expect(todos.single.lastSyncedAt, isNull);

    await (database.update(
      database.todoItems,
    )..where((row) => row.id.equals(id))).write(
      TodoItemsCompanion(
        syncStatus: const Value('synced'),
        lastSyncedAt: Value(DateTime(2026, 6, 4)),
      ),
    );

    await todoRepository.updateTodo(id: id, isCompleted: true);
    todos = await todoRepository.getTodosForDate(date);
    expect(todos.single.isCompleted, isTrue);
    expect(todos.single.syncStatus, TodoRepository.pendingSyncStatus);

    await todoRepository.deleteTodo(id);
    todos = await todoRepository.getTodosForDate(date);
    expect(todos, isEmpty);

    final deleted = await todoRepository.getTodoByIdIncludingDeleted(id);
    expect(deleted, isNotNull);
    expect(deleted!.deletedAt, isNotNull);
    expect(deleted.syncStatus, TodoRepository.pendingSyncStatus);
  });

  test('生日和纪念日生成 UUID，删除为软删除并被默认查询过滤', () async {
    final id = await recurringEventRepository.addEvent(
      title: '妈妈生日',
      eventType: EventType.birthday,
      calendarType: CalendarType.solar,
      month: 8,
      day: 16,
    );
    expect(id, matches(_uuidPattern));

    var events = await recurringEventRepository.getEvents();
    expect(events, hasLength(1));
    expect(events.single.id, id);
    expect(events.single.deletedAt, isNull);
    expect(
      events.single.syncStatus,
      RecurringEventRepository.pendingSyncStatus,
    );
    expect(events.single.lastSyncedAt, isNull);

    await recurringEventRepository.deleteEvent(id);
    events = await recurringEventRepository.getEvents();
    expect(events, isEmpty);

    final deleted = await recurringEventRepository.getEventByIdIncludingDeleted(
      id,
    );
    expect(deleted, isNotNull);
    expect(deleted!.deletedAt, isNotNull);
    expect(deleted.syncStatus, RecurringEventRepository.pendingSyncStatus);
  });
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
