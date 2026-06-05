import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_repository.dart';
import 'package:zrk_calendar/features/todo/todo_repository.dart';

void main() {
  test('schema v1 数据迁移到 v2 时保留记录并生成同步字段', () async {
    final directory = await Directory.systemTemp.createTemp(
      'zrk_calendar_migration_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/zrk_calendar.sqlite');
    _createV1Database(file);

    final database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);

    final todos = await database.select(database.todoItems).get();
    expect(todos, hasLength(1));
    expect(todos.single.id, matches(_uuidPattern));
    expect(todos.single.title, '旧待办');
    expect(todos.single.deletedAt, isNull);
    expect(todos.single.syncStatus, TodoRepository.pendingSyncStatus);
    expect(todos.single.lastSyncedAt, isNull);

    final events = await database.select(database.recurringEvents).get();
    expect(events, hasLength(1));
    expect(events.single.id, matches(_uuidPattern));
    expect(events.single.title, '旧生日');
    expect(events.single.deletedAt, isNull);
    expect(
      events.single.syncStatus,
      RecurringEventRepository.pendingSyncStatus,
    );
    expect(events.single.lastSyncedAt, isNull);
  });
}

void _createV1Database(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('''
CREATE TABLE todo_items (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  date INTEGER NOT NULL,
  is_completed INTEGER NOT NULL DEFAULT 0 CHECK ("is_completed" IN (0, 1)),
  note TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
    database.execute('''
CREATE TABLE recurring_events (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  event_type TEXT NOT NULL,
  calendar_type TEXT NOT NULL,
  month INTEGER NOT NULL,
  day INTEGER NOT NULL,
  is_leap_month INTEGER NOT NULL DEFAULT 0 CHECK ("is_leap_month" IN (0, 1)),
  leap_month_policy TEXT NOT NULL DEFAULT 'useNormalMonth',
  note TEXT NULL,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK ("enabled" IN (0, 1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
''');
    final now = DateTime(2026, 6, 5).millisecondsSinceEpoch;
    final date = DateTime(2026, 6, 6).millisecondsSinceEpoch;
    database.execute(
      '''
INSERT INTO todo_items (
  title,
  date,
  is_completed,
  note,
  created_at,
  updated_at
) VALUES (?, ?, 0, NULL, ?, ?);
''',
      ['旧待办', date, now, now],
    );
    database.execute(
      '''
INSERT INTO recurring_events (
  title,
  event_type,
  calendar_type,
  month,
  day,
  is_leap_month,
  leap_month_policy,
  note,
  enabled,
  created_at,
  updated_at
) VALUES (?, 'birthday', 'solar', 8, 16, 0, 'useNormalMonth', NULL, 1, ?, ?);
''',
      ['旧生日', now, now],
    );
    database.execute('PRAGMA user_version = 1;');
  } finally {
    database.close();
  }
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
