enum EventType {
  birthday('birthday', '生日'),
  anniversary('anniversary', '纪念日');

  const EventType(this.value, this.label);

  final String value;
  final String label;

  static EventType fromValue(String value) {
    return EventType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => EventType.birthday,
    );
  }
}

enum CalendarType {
  solar('solar', '公历'),
  lunar('lunar', '农历');

  const CalendarType(this.value, this.label);

  final String value;
  final String label;

  static CalendarType fromValue(String value) {
    return CalendarType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => CalendarType.solar,
    );
  }
}

enum LeapMonthPolicy {
  useNormalMonth('useNormalMonth', '按普通月份提醒'),
  skipThisYear('skipThisYear', '当年跳过');

  const LeapMonthPolicy(this.value, this.label);

  final String value;
  final String label;

  static LeapMonthPolicy fromValue(String value) {
    return LeapMonthPolicy.values.firstWhere(
      (policy) => policy.value == value,
      orElse: () => LeapMonthPolicy.useNormalMonth,
    );
  }
}

class EventOccurrence {
  const EventOccurrence({
    required this.id,
    required this.title,
    required this.eventType,
    required this.calendarType,
    required this.date,
    this.note,
  });

  final int id;
  final String title;
  final EventType eventType;
  final CalendarType calendarType;
  final DateTime date;
  final String? note;
}
