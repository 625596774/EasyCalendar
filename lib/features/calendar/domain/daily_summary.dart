import '../../../shared/utils/date_utils.dart';

class DailySummary {
  const DailySummary({
    required this.date,
    required this.weekday,
    required this.lunarText,
    required this.festivals,
    required this.officialHolidayStatus,
    required this.recurringEvents,
    required this.todos,
    required this.generatedAt,
  });

  final DateTime date;
  final String weekday;
  final String lunarText;
  final List<String> festivals;
  final DailyOfficialHolidayStatus? officialHolidayStatus;
  final List<DailyRecurringEventSummary> recurringEvents;
  final List<DailyTodoSummary> todos;
  final DateTime generatedAt;

  Map<String, Object?> toJson() {
    return {
      'date': dateKey(date),
      'weekday': weekday,
      'lunarText': lunarText,
      'festivals': festivals,
      'officialHolidayStatus': officialHolidayStatus?.toJson(),
      'recurringEvents': recurringEvents
          .map((event) => event.toJson())
          .toList(growable: false),
      'todos': todos.map((todo) => todo.toJson()).toList(growable: false),
      'generatedAt': generatedAt.toUtc().toIso8601String(),
    };
  }
}

class DailyOfficialHolidayStatus {
  const DailyOfficialHolidayStatus({
    required this.name,
    required this.status,
    required this.label,
  });

  final String name;
  final String status;
  final String label;

  Map<String, Object?> toJson() {
    return {'name': name, 'status': status, 'label': label};
  }
}

class DailyRecurringEventSummary {
  const DailyRecurringEventSummary({
    required this.id,
    required this.title,
    required this.eventType,
    required this.eventTypeLabel,
    required this.calendarType,
    required this.calendarTypeLabel,
    this.note,
  });

  final String id;
  final String title;
  final String eventType;
  final String eventTypeLabel;
  final String calendarType;
  final String calendarTypeLabel;
  final String? note;

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'eventType': eventType,
      'eventTypeLabel': eventTypeLabel,
      'calendarType': calendarType,
      'calendarTypeLabel': calendarTypeLabel,
    };
  }
}

class DailyTodoSummary {
  const DailyTodoSummary({
    required this.id,
    required this.title,
    required this.isCompleted,
    this.note,
  });

  final String id;
  final String title;
  final bool isCompleted;
  final String? note;

  Map<String, Object?> toJson() {
    return {'id': id, 'title': title, 'isCompleted': isCompleted};
  }
}
