import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../shared/utils/date_utils.dart';

class TodoRepository {
  TodoRepository(this._database);

  final AppDatabase _database;

  Stream<List<TodoItem>> watchTodosForRange(DateTime start, DateTime end) {
    final normalizedStart = dateOnly(start);
    final normalizedEnd = dateOnly(end);
    return (_database.select(_database.todoItems)
          ..where((row) => row.date.isBetweenValues(normalizedStart, normalizedEnd))
          ..orderBy([
            (row) => OrderingTerm(expression: row.isCompleted),
            (row) => OrderingTerm(expression: row.createdAt),
          ]))
        .watch();
  }

  Stream<List<TodoItem>> watchTodosForDate(DateTime date) {
    final day = dateOnly(date);
    return (_database.select(_database.todoItems)
          ..where((row) => row.date.equals(day))
          ..orderBy([
            (row) => OrderingTerm(expression: row.isCompleted),
            (row) => OrderingTerm(expression: row.createdAt),
          ]))
        .watch();
  }

  Future<List<TodoItem>> getTodosForDate(DateTime date) {
    final day = dateOnly(date);
    return (_database.select(_database.todoItems)
          ..where((row) => row.date.equals(day))
          ..orderBy([
            (row) => OrderingTerm(expression: row.isCompleted),
            (row) => OrderingTerm(expression: row.createdAt),
          ]))
        .get();
  }

  Future<int> addTodo({
    required String title,
    required DateTime date,
    String? note,
  }) {
    final now = DateTime.now();
    return _database.into(_database.todoItems).insert(
          TodoItemsCompanion.insert(
            title: title.trim(),
            date: dateOnly(date),
            note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> updateTodo({
    required int id,
    String? title,
    bool? isCompleted,
    String? note,
  }) {
    return (_database.update(_database.todoItems)..where((row) => row.id.equals(id)))
        .write(
      TodoItemsCompanion(
        title: title == null ? const Value.absent() : Value(title.trim()),
        isCompleted:
            isCompleted == null ? const Value.absent() : Value(isCompleted),
        note: note == null
            ? const Value.absent()
            : Value(note.trim().isEmpty ? null : note.trim()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteTodo(int id) {
    return (_database.delete(_database.todoItems)..where((row) => row.id.equals(id)))
        .go();
  }
}
