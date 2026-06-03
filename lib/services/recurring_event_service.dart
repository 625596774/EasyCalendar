import '../database/app_database.dart';
import '../features/recurring_event/recurring_event_models.dart';
import 'lunar_calendar_service.dart';

class RecurringEventService {
  RecurringEventService(this._lunarCalendarService);

  final LunarCalendarService _lunarCalendarService;

  EventOccurrence? occurrenceForYear(RecurringEvent event, int year) {
    if (!event.enabled) {
      return null;
    }

    final calendarType = CalendarType.fromValue(event.calendarType);
    final eventType = EventType.fromValue(event.eventType);

    if (calendarType == CalendarType.solar) {
      final date = _safeDate(year, event.month, event.day);
      if (date == null) {
        return null;
      }
      return EventOccurrence(
        id: event.id,
        title: event.title,
        eventType: eventType,
        calendarType: calendarType,
        date: date,
        note: event.note,
      );
    }

    final policy = LeapMonthPolicy.fromValue(event.leapMonthPolicy);
    var useLeapMonth = event.isLeapMonth;
    if (event.isLeapMonth &&
        !_lunarCalendarService.hasLeapMonth(year, event.month)) {
      if (policy == LeapMonthPolicy.skipThisYear) {
        return null;
      }
      useLeapMonth = false;
    }

    final date = _lunarCalendarService.toSolar(
      lunarYear: year,
      lunarMonth: event.month,
      lunarDay: event.day,
      isLeapMonth: useLeapMonth,
    );
    if (date == null) {
      return null;
    }
    return EventOccurrence(
      id: event.id,
      title: event.title,
      eventType: eventType,
      calendarType: calendarType,
      date: date,
      note: event.note,
    );
  }

  List<EventOccurrence> occurrencesForYear(
    List<RecurringEvent> events,
    int year,
  ) {
    return events
        .map((event) => occurrenceForYear(event, year))
        .whereType<EventOccurrence>()
        .toList();
  }

  Map<String, List<EventOccurrence>> occurrencesByDate(
    List<RecurringEvent> events,
    Iterable<int> years,
  ) {
    final result = <String, List<EventOccurrence>>{};
    for (final year in years.toSet()) {
      for (final occurrence in occurrencesForYear(events, year)) {
        final key = _dateKey(occurrence.date);
        result.putIfAbsent(key, () => []).add(occurrence);
      }
    }
    return result;
  }

  DateTime? _safeDate(int year, int month, int day) {
    try {
      final date = DateTime(year, month, day);
      if (date.year != year || date.month != month || date.day != day) {
        return null;
      }
      return date;
    } catch (_) {
      return null;
    }
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
