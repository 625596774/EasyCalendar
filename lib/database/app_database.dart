import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class TodoItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  DateTimeColumn get date => dateTime()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

class RecurringEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
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
}

@DriftDatabase(tables: [TodoItems, RecurringEvents])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;
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
