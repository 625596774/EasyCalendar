import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'recurring_event_models.dart';

class RecurringEventRepository {
  RecurringEventRepository(this._database);

  final AppDatabase _database;

  Stream<List<RecurringEvent>> watchEvents() {
    return (_database.select(_database.recurringEvents)
          ..orderBy([
            (row) => OrderingTerm(expression: row.enabled, mode: OrderingMode.desc),
            (row) => OrderingTerm(expression: row.calendarType),
            (row) => OrderingTerm(expression: row.month),
            (row) => OrderingTerm(expression: row.day),
          ]))
        .watch();
  }

  Future<List<RecurringEvent>> getEvents({bool enabledOnly = false}) {
    final query = _database.select(_database.recurringEvents)
      ..orderBy([
        (row) => OrderingTerm(expression: row.calendarType),
        (row) => OrderingTerm(expression: row.month),
        (row) => OrderingTerm(expression: row.day),
      ]);
    if (enabledOnly) {
      query.where((row) => row.enabled.equals(true));
    }
    return query.get();
  }

  Future<int> addEvent({
    required String title,
    required EventType eventType,
    required CalendarType calendarType,
    required int month,
    required int day,
    bool isLeapMonth = false,
    LeapMonthPolicy leapMonthPolicy = LeapMonthPolicy.useNormalMonth,
    String? note,
    bool enabled = true,
  }) {
    final now = DateTime.now();
    return _database.into(_database.recurringEvents).insert(
          RecurringEventsCompanion.insert(
            title: title.trim(),
            eventType: eventType.value,
            calendarType: calendarType.value,
            month: month,
            day: day,
            isLeapMonth: Value(isLeapMonth),
            leapMonthPolicy: Value(leapMonthPolicy.value),
            note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
            enabled: Value(enabled),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  Future<void> updateEvent({
    required int id,
    required String title,
    required EventType eventType,
    required CalendarType calendarType,
    required int month,
    required int day,
    required bool isLeapMonth,
    required LeapMonthPolicy leapMonthPolicy,
    required String? note,
    required bool enabled,
  }) {
    return (_database.update(_database.recurringEvents)
          ..where((row) => row.id.equals(id)))
        .write(
      RecurringEventsCompanion(
        title: Value(title.trim()),
        eventType: Value(eventType.value),
        calendarType: Value(calendarType.value),
        month: Value(month),
        day: Value(day),
        isLeapMonth: Value(isLeapMonth),
        leapMonthPolicy: Value(leapMonthPolicy.value),
        note: Value(note?.trim().isEmpty ?? true ? null : note!.trim()),
        enabled: Value(enabled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteEvent(int id) {
    return (_database.delete(_database.recurringEvents)
          ..where((row) => row.id.equals(id)))
        .go();
  }
}
