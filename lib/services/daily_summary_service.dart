import '../features/calendar/domain/daily_summary.dart';
import '../features/recurring_event/recurring_event_models.dart';
import '../features/recurring_event/recurring_event_repository.dart';
import '../features/todo/todo_repository.dart';
import '../shared/utils/date_utils.dart';
import 'festival_service.dart';
import 'lunar_calendar_service.dart';
import 'official_holiday_service.dart';
import 'recurring_event_service.dart';

class DailySummaryService {
  DailySummaryService({
    required TodoRepository todoRepository,
    required RecurringEventRepository recurringEventRepository,
    required LunarCalendarService lunarCalendarService,
    required FestivalService festivalService,
    required OfficialHolidayService officialHolidayService,
    required RecurringEventService recurringEventService,
  }) : this._(
         todoRepository,
         recurringEventRepository,
         lunarCalendarService,
         festivalService,
         officialHolidayService,
         recurringEventService,
       );

  DailySummaryService._(
    this._todoRepository,
    this._recurringEventRepository,
    this._lunarCalendarService,
    this._festivalService,
    this._officialHolidayService,
    this._recurringEventService,
  );

  final TodoRepository _todoRepository;
  final RecurringEventRepository _recurringEventRepository;
  final LunarCalendarService _lunarCalendarService;
  final FestivalService _festivalService;
  final OfficialHolidayService _officialHolidayService;
  final RecurringEventService _recurringEventService;

  Future<DailySummary> buildForDate(
    DateTime date, {
    DateTime? generatedAt,
  }) async {
    final day = dateOnly(date);
    await _officialHolidayService.loadYear(day.year);

    final lunarInfo = _lunarCalendarService.fromSolar(day);
    final holiday = _officialHolidayService.getForDate(day);
    final todos = await _todoRepository.getTodosForDate(day);
    final recurringEvents = await _recurringEventRepository.getEvents(
      enabledOnly: true,
    );
    final occurrenceMap = _recurringEventService.occurrencesByDate(
      recurringEvents,
      {day.year - 1, day.year, day.year + 1},
    );

    return DailySummary(
      date: day,
      weekday: weekdayName(day),
      lunarText: lunarInfo.fullText,
      festivals: _festivalService.festivalsFor(day),
      officialHolidayStatus: holiday == null
          ? null
          : DailyOfficialHolidayStatus(
              name: holiday.name,
              status: holiday.status.value,
              label: holiday.status.label,
            ),
      recurringEvents: (occurrenceMap[dateKey(day)] ?? const [])
          .map(_occurrenceToSummary)
          .toList(growable: false),
      todos: todos
          .map(
            (todo) => DailyTodoSummary(
              id: todo.id,
              title: todo.title,
              isCompleted: todo.isCompleted,
              note: todo.note,
            ),
          )
          .toList(growable: false),
      generatedAt: (generatedAt ?? DateTime.now()).toUtc(),
    );
  }

  DailyRecurringEventSummary _occurrenceToSummary(EventOccurrence occurrence) {
    return DailyRecurringEventSummary(
      id: occurrence.id,
      title: occurrence.title,
      eventType: occurrence.eventType.value,
      eventTypeLabel: occurrence.eventType.label,
      calendarType: occurrence.calendarType.value,
      calendarTypeLabel: occurrence.calendarType.label,
      note: occurrence.note,
    );
  }
}
