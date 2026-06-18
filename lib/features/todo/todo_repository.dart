import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../../services/sync/sync_models.dart';
import '../../shared/utils/date_utils.dart';

abstract final class TodoUrgency {
  static const red = 'red';
  static const yellow = 'yellow';
  static const green = 'green';
  static const values = [red, yellow, green];

  static String normalize(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return green;
    }
    if (values.contains(normalized)) {
      return normalized;
    }
    throw ArgumentError.value(value, 'urgency', '待办紧急程度无效。');
  }
}

class TodoRepository {
  TodoRepository(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const pendingSyncStatus = SyncRecordStatus.pending;
  static const syncedSyncStatus = SyncRecordStatus.synced;
  static const failedSyncStatus = SyncRecordStatus.failed;
  static const unnamedTodoTitle = '未命名待办';

  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<TodoItem>> watchTodosForRange(DateTime start, DateTime end) {
    final normalizedStart = dateOnly(start);
    final normalizedEnd = dateOnly(end);
    return (_database.select(_database.todoItems)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.date.isBetweenValues(normalizedStart, normalizedEnd),
          )
          ..orderBy([
            (row) => OrderingTerm(expression: row.isCompleted),
            (row) => OrderingTerm(expression: row.createdAt),
          ]))
        .watch()
        .map(_sortTodosForDisplay);
  }

  Stream<List<TodoItem>> watchTodosForDate(DateTime date) {
    final day = dateOnly(date);
    return (_database.select(_database.todoItems)
          ..where((row) => row.deletedAt.isNull() & row.date.equals(day))
          ..orderBy([
            (row) => OrderingTerm(expression: row.isCompleted),
            (row) => OrderingTerm(expression: row.createdAt),
          ]))
        .watch()
        .map(_sortTodosForDisplay);
  }

  Future<List<TodoItem>> getTodosForDate(DateTime date) async {
    final day = dateOnly(date);
    final todos = await (_database.select(_database.todoItems)
          ..where((row) => row.deletedAt.isNull() & row.date.equals(day))
          ..orderBy([
            (row) => OrderingTerm(expression: row.isCompleted),
            (row) => OrderingTerm(expression: row.createdAt),
          ]))
        .get();
    return _sortTodosForDisplay(todos);
  }

  Future<TodoItem?> getTodoByIdIncludingDeleted(String id) {
    return (_database.select(
      _database.todoItems,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Future<List<TodoItem>> getPendingTodosIncludingDeleted() {
    return (_database.select(_database.todoItems)..where(
          (row) =>
              row.syncStatus.equals(pendingSyncStatus) |
              row.syncStatus.equals(failedSyncStatus),
        ))
        .get();
  }

  Future<bool> hasPendingTodosIncludingDeleted() async {
    final todo =
        await (_database.select(_database.todoItems)
              ..where(
                (row) =>
                    row.syncStatus.equals(pendingSyncStatus) |
                    row.syncStatus.equals(failedSyncStatus),
              )
              ..limit(1))
            .getSingleOrNull();
    return todo != null;
  }

  Future<List<TodoItem>> getAllTodosIncludingDeleted() {
    return _database.select(_database.todoItems).get();
  }

  Future<String> addTodo({
    required String title,
    required DateTime date,
    String urgency = TodoUrgency.green,
    String? note,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', '待办标题不能为空。');
    }
    final normalizedUrgency = TodoUrgency.normalize(urgency);
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _database
        .into(_database.todoItems)
        .insert(
          TodoItemsCompanion.insert(
            id: id,
            title: normalizedTitle,
            date: dateOnly(date),
            urgency: Value(normalizedUrgency),
            note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
            createdAt: now,
            updatedAt: now,
            syncStatus: const Value(pendingSyncStatus),
          ),
        );
    return id;
  }

  Future<void> updateTodo({
    required String id,
    String? title,
    bool? isCompleted,
    String? urgency,
    String? note,
  }) {
    final normalizedTitle = title?.trim();
    if (normalizedTitle != null && normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', '待办标题不能为空。');
    }
    final normalizedUrgency = urgency == null
        ? null
        : TodoUrgency.normalize(urgency);
    return (_database.update(
      _database.todoItems,
    )..where((row) => row.id.equals(id))).write(
      TodoItemsCompanion(
        title: normalizedTitle == null
            ? const Value.absent()
            : Value(normalizedTitle),
        isCompleted: isCompleted == null
            ? const Value.absent()
            : Value(isCompleted),
        urgency: normalizedUrgency == null
            ? const Value.absent()
            : Value(normalizedUrgency),
        note: note == null
            ? const Value.absent()
            : Value(note.trim().isEmpty ? null : note.trim()),
        updatedAt: Value(DateTime.now().toUtc()),
        syncStatus: const Value(pendingSyncStatus),
      ),
    );
  }

  Future<int> moveIncompleteTodosBeforeDate({
    required DateTime beforeDate,
    required DateTime targetDate,
  }) {
    final normalizedBeforeDate = dateOnly(beforeDate);
    final normalizedTargetDate = dateOnly(targetDate);
    final now = DateTime.now().toUtc();
    return (_database.update(_database.todoItems)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.isCompleted.equals(false) &
                row.date.isSmallerThanValue(normalizedBeforeDate),
          ))
        .write(
          TodoItemsCompanion(
            date: Value(normalizedTargetDate),
            updatedAt: Value(now),
            syncStatus: const Value(pendingSyncStatus),
          ),
        );
  }

  Future<void> deleteTodo(String id) {
    final now = DateTime.now().toUtc();
    return (_database.update(
      _database.todoItems,
    )..where((row) => row.id.equals(id))).write(
      TodoItemsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(pendingSyncStatus),
      ),
    );
  }

  Future<void> upsertFromSync(
    TodoSyncRecord record, {
    required DateTime syncedAt,
  }) async {
    final existing = await getTodoByIdIncludingDeleted(record.id);
    if (existing == null) {
      await _database
          .into(_database.todoItems)
          .insert(
            TodoItemsCompanion.insert(
              id: record.id,
              title: record.title,
              date: dateOnly(record.date),
              isCompleted: Value(record.isCompleted),
              urgency: Value(TodoUrgency.normalize(record.urgency)),
              note: Value(record.note),
              createdAt: record.createdAt.toUtc(),
              updatedAt: record.updatedAt.toUtc(),
              deletedAt: Value(record.deletedAt?.toUtc()),
              syncStatus: const Value(syncedSyncStatus),
              lastSyncedAt: Value(syncedAt.toUtc()),
            ),
          );
      return;
    }
    await (_database.update(
      _database.todoItems,
    )..where((row) => row.id.equals(record.id))).write(
      TodoItemsCompanion(
        title: Value(record.title),
        date: Value(dateOnly(record.date)),
        isCompleted: Value(record.isCompleted),
        urgency: Value(TodoUrgency.normalize(record.urgency)),
        note: Value(record.note),
        createdAt: Value(record.createdAt.toUtc()),
        updatedAt: Value(record.updatedAt.toUtc()),
        deletedAt: Value(record.deletedAt?.toUtc()),
        syncStatus: const Value(syncedSyncStatus),
        lastSyncedAt: Value(syncedAt.toUtc()),
      ),
    );
  }

  Future<void> markTodoSynced(String id, DateTime syncedAt) {
    return (_database.update(
      _database.todoItems,
    )..where((row) => row.id.equals(id))).write(
      TodoItemsCompanion(
        syncStatus: const Value(syncedSyncStatus),
        lastSyncedAt: Value(syncedAt.toUtc()),
      ),
    );
  }

  Future<void> markTodoSyncFailed(String id) {
    return (_database.update(_database.todoItems)
          ..where((row) => row.id.equals(id)))
        .write(const TodoItemsCompanion(syncStatus: Value(failedSyncStatus)));
  }

  Future<int> repairEmptyPendingTodoTitlesForSync() async {
    final pendingTodos = await getPendingTodosIncludingDeleted();
    final invalidTodos = pendingTodos
        .where((todo) => todo.title.trim().isEmpty)
        .toList(growable: false);
    for (final todo in invalidTodos) {
      await (_database.update(
        _database.todoItems,
      )..where((row) => row.id.equals(todo.id))).write(
        const TodoItemsCompanion(
          title: Value(unnamedTodoTitle),
          syncStatus: Value(pendingSyncStatus),
        ),
      );
    }
    return invalidTodos.length;
  }
}

List<TodoItem> _sortTodosForDisplay(List<TodoItem> todos) {
  final sorted = todos.toList(growable: false);
  sorted.sort((a, b) {
    final completedComparison = a.isCompleted == b.isCompleted
        ? 0
        : a.isCompleted
        ? 1
        : -1;
    if (completedComparison != 0) {
      return completedComparison;
    }
    final urgencyComparison = _urgencyRank(
      a.urgency,
    ).compareTo(_urgencyRank(b.urgency));
    if (urgencyComparison != 0) {
      return urgencyComparison;
    }
    return a.createdAt.compareTo(b.createdAt);
  });
  return sorted;
}

int _urgencyRank(String urgency) {
  return switch (urgency) {
    TodoUrgency.red => 0,
    TodoUrgency.yellow => 1,
    TodoUrgency.green => 2,
    _ => 2,
  };
}
