import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_models.dart';
import 'package:zrk_calendar/services/lunar_calendar_service.dart';
import 'package:zrk_calendar/services/recurring_event_service.dart';

void main() {
  final service = RecurringEventService(LunarCalendarService());
  final now = DateTime(2026, 1, 1);

  RecurringEvent event({
    required String calendarType,
    required int month,
    required int day,
    bool isLeapMonth = false,
    String leapMonthPolicy = 'useNormalMonth',
  }) {
    return RecurringEvent(
      id: 'event-1',
      title: '测试生日',
      eventType: EventType.birthday.value,
      calendarType: calendarType,
      month: month,
      day: day,
      isLeapMonth: isLeapMonth,
      leapMonthPolicy: leapMonthPolicy,
      note: null,
      enabled: true,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      syncStatus: 'pending',
      lastSyncedAt: null,
    );
  }

  test('公历生日按年生成', () {
    final occurrence = service.occurrenceForYear(
      event(calendarType: 'solar', month: 8, day: 16),
      2027,
    );
    expect(occurrence?.date, DateTime(2027, 8, 16));
  });

  test('农历生日按年生成', () {
    final occurrence = service.occurrenceForYear(
      event(calendarType: 'lunar', month: 8, day: 15),
      2026,
    );
    expect(occurrence?.date, DateTime(2026, 9, 25));
  });

  test('闰月不存在时 useNormalMonth 使用普通月份', () {
    final occurrence = service.occurrenceForYear(
      event(calendarType: 'lunar', month: 8, day: 15, isLeapMonth: true),
      2026,
    );
    expect(occurrence?.date, DateTime(2026, 9, 25));
  });

  test('闰月不存在时 skipThisYear 跳过', () {
    final occurrence = service.occurrenceForYear(
      event(
        calendarType: 'lunar',
        month: 8,
        day: 15,
        isLeapMonth: true,
        leapMonthPolicy: 'skipThisYear',
      ),
      2026,
    );
    expect(occurrence, isNull);
  });
}
