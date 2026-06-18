import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class TodoItems extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  DateTimeColumn get date => dateTime()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  TextColumn get urgency => text().withDefault(const Constant('green'))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class RecurringEvents extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get eventType => text()();
  TextColumn get calendarType => text()();
  IntColumn get month => integer()();
  IntColumn get day => integer()();
  BoolColumn get isLeapMonth => boolean().withDefault(const Constant(false))();
  TextColumn get leapMonthPolicy =>
      text().withDefault(const Constant('useNormalMonth'))();
  TextColumn get note => text().nullable()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus => text().withDefault(const Constant('pending'))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [TodoItems, RecurringEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (_, from, to) async {
        if (from < 2) {
          await transaction(_migrateFromV1ToV2);
        }
        if (from < 3) {
          await _migrateToV3();
        }
      },
    );
  }

  Future<void> _migrateToV3() async {
    await customStatement(
      "ALTER TABLE todo_items ADD COLUMN urgency TEXT NOT NULL DEFAULT 'green';",
    );
  }

  Future<void> _migrateFromV1ToV2() async {
    await customStatement('''
CREATE TABLE todo_items_new (
  id TEXT NOT NULL PRIMARY KEY,
  title TEXT NOT NULL,
  date INTEGER NOT NULL,
  is_completed INTEGER NOT NULL DEFAULT 0 CHECK ("is_completed" IN (0, 1)),
  note TEXT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER NULL,
  sync_status TEXT NOT NULL DEFAULT 'pending',
  last_synced_at INTEGER NULL
);
''');
    await customStatement('''
INSERT INTO todo_items_new (
  id,
  title,
  date,
  is_completed,
  note,
  created_at,
  updated_at,
  deleted_at,
  sync_status,
  last_synced_at
)
SELECT
  ${_sqliteUuidExpression()},
  title,
  date,
  is_completed,
  note,
  created_at,
  updated_at,
  NULL,
  'pending',
  NULL
FROM todo_items;
''');
    await customStatement('DROP TABLE todo_items;');
    await customStatement('ALTER TABLE todo_items_new RENAME TO todo_items;');

    await customStatement('''
CREATE TABLE recurring_events_new (
  id TEXT NOT NULL PRIMARY KEY,
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
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER NULL,
  sync_status TEXT NOT NULL DEFAULT 'pending',
  last_synced_at INTEGER NULL
);
''');
    await customStatement('''
INSERT INTO recurring_events_new (
  id,
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
  updated_at,
  deleted_at,
  sync_status,
  last_synced_at
)
SELECT
  ${_sqliteUuidExpression()},
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
  updated_at,
  NULL,
  'pending',
  NULL
FROM recurring_events;
''');
    await customStatement('DROP TABLE recurring_events;');
    await customStatement(
      'ALTER TABLE recurring_events_new RENAME TO recurring_events;',
    );
  }
}

String _sqliteUuidExpression() {
  return '''
lower(hex(randomblob(4))) || '-' ||
lower(hex(randomblob(2))) || '-' ||
'4' || substr(lower(hex(randomblob(2))), 2) || '-' ||
substr('89ab', (abs(random()) % 4) + 1, 1) ||
substr(lower(hex(randomblob(2))), 2) || '-' ||
lower(hex(randomblob(6)))
''';
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final appDir = Directory(p.join(directory.path, 'zrk_calendar'));
    if (!appDir.existsSync()) {
      appDir.createSync(recursive: true);
    }
    final file = File(p.join(appDir.path, 'zrk_calendar.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
