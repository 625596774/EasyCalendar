import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import 'recurring_event_models.dart';

class RecurringEventRepository {
  RecurringEventRepository(this._database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  static const pendingSyncStatus = 'pending';

  final AppDatabase _database;
  final Uuid _uuid;

  Stream<List<RecurringEvent>> watchEvents() {
    return (_database.select(_database.recurringEvents)
          ..where((row) => row.deletedAt.isNull())
          ..orderBy([
            (row) =>
                OrderingTerm(expression: row.enabled, mode: OrderingMode.desc),
            (row) => OrderingTerm(expression: row.calendarType),
            (row) => OrderingTerm(expression: row.month),
            (row) => OrderingTerm(expression: row.day),
          ]))
        .watch();
  }

  Future<List<RecurringEvent>> getEvents({bool enabledOnly = false}) {
    final query = _database.select(_database.recurringEvents)
      ..where((row) => row.deletedAt.isNull())
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

  Future<RecurringEvent?> getEventByIdIncludingDeleted(String id) {
    return (_database.select(
      _database.recurringEvents,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  Future<List<RecurringEvent>> getEventsIncludingDeleted() {
    return _database.select(_database.recurringEvents).get();
  }

  Future<String> addEvent({
    required String title,
    required EventType eventType,
    required CalendarType calendarType,
    required int month,
    required int day,
    bool isLeapMonth = false,
    LeapMonthPolicy leapMonthPolicy = LeapMonthPolicy.useNormalMonth,
    String? note,
    bool enabled = true,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _database
        .into(_database.recurringEvents)
        .insert(
          RecurringEventsCompanion.insert(
            id: id,
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
            syncStatus: const Value(pendingSyncStatus),
          ),
        );
    return id;
  }

  Future<void> updateEvent({
    required String id,
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
    return (_database.update(
      _database.recurringEvents,
    )..where((row) => row.id.equals(id))).write(
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
        syncStatus: const Value(pendingSyncStatus),
      ),
    );
  }

  Future<void> deleteEvent(String id) {
    final now = DateTime.now();
    return (_database.update(
      _database.recurringEvents,
    )..where((row) => row.id.equals(id))).write(
      RecurringEventsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncStatus: const Value(pendingSyncStatus),
      ),
    );
  }
}
