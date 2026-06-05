import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../../shared/utils/date_utils.dart';

class TodoRepository {
  TodoRepository(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static const pendingSyncStatus = 'pending';

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
        .watch();
  }

  Stream<List<TodoItem>> watchTodosForDate(DateTime date) {
    final day = dateOnly(date);
    return (_database.select(_database.todoItems)
          ..where((row) => row.deletedAt.isNull() & row.date.equals(day))
          ..orderBy([
            (row) => OrderingTerm(expression: row.isCompleted),
            (row) => OrderingTerm(expression: row.createdAt),
          ]))
        .watch();
  }

  Future<List<TodoItem>> getTodosForDate(DateTime date) {
    final day = dateOnly(date);
    return (_database.select(_database.todoItems)
          ..where((row) => row.deletedAt.isNull() & row.date.equals(day))
          ..orderBy([
            (row) => OrderingTerm(expression: row.isCompleted),
            (row) => OrderingTerm(expression: row.createdAt),
          ]))
        .get();
  }

  Future<TodoItem?> getTodoByIdIncludingDeleted(String id) {
    return (_database.select(
      _database.todoItems,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Future<String> addTodo({
    required String title,
    required DateTime date,
    String? note,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _database
        .into(_database.todoItems)
        .insert(
          TodoItemsCompanion.insert(
            id: id,
            title: title.trim(),
            date: dateOnly(date),
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
    String? note,
  }) {
    return (_database.update(
      _database.todoItems,
    )..where((row) => row.id.equals(id))).write(
      TodoItemsCompanion(
        title: title == null ? const Value.absent() : Value(title.trim()),
        isCompleted: isCompleted == null
            ? const Value.absent()
            : Value(isCompleted),
        note: note == null
            ? const Value.absent()
            : Value(note.trim().isEmpty ? null : note.trim()),
        updatedAt: Value(DateTime.now()),
        syncStatus: const Value(pendingSyncStatus),
      ),
    );
  }

  Future<void> deleteTodo(String id) {
    final now = DateTime.now();
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
}
