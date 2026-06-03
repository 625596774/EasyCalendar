import '../../../database/app_database.dart';
import '../../../features/recurring_event/recurring_event_models.dart';
import '../../../services/lunar_calendar_service.dart';
import '../../../services/official_holiday_service.dart';

class CalendarDay {
  const CalendarDay({
    required this.date,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isSelected,
    required this.lunarInfo,
    required this.festivals,
    required this.todos,
    required this.recurringEvents,
    required this.officialHoliday,
  });

  final DateTime date;
  final bool isCurrentMonth;
  final bool isToday;
  final bool isSelected;
  final LunarDateInfo lunarInfo;
  final List<String> festivals;
  final List<TodoItem> todos;
  final List<EventOccurrence> recurringEvents;
  final OfficialHolidayItem? officialHoliday;
}
