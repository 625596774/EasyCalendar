import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/todo/todo_repository.dart';

void main() {
  late AppDatabase database;
  late TodoRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = TodoRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('待办写入、更新完成状态、删除', () async {
    final date = DateTime(2026, 6, 3);
    final id = await repository.addTodo(title: '写第一版日历', date: date);

    var todos = await repository.getTodosForDate(date);
    expect(todos, hasLength(1));
    expect(todos.single.id, id);
    expect(todos.single.isCompleted, isFalse);

    await repository.updateTodo(id: id, isCompleted: true);
    todos = await repository.getTodosForDate(date);
    expect(todos.single.isCompleted, isTrue);

    await repository.deleteTodo(id);
    todos = await repository.getTodosForDate(date);
    expect(todos, isEmpty);
  });
}
