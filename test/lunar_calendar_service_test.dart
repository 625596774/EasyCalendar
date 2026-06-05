import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/services/lunar_calendar_service.dart';

void main() {
  final service = LunarCalendarService();

  test('公历日期转农历日期', () {
    final springFestival2026 = service.fromSolar(DateTime(2026, 2, 17));
    expect(springFestival2026.month, 1);
    expect(springFestival2026.day, 1);
    expect(springFestival2026.dayText, '初一');

    final midAutumn2026 = service.fromSolar(DateTime(2026, 9, 25));
    expect(midAutumn2026.month, 8);
    expect(midAutumn2026.day, 15);
    expect(midAutumn2026.dayText, '十五');
  });

  test('农历转公历', () {
    expect(
      service.toSolar(lunarYear: 2026, lunarMonth: 1, lunarDay: 1),
      DateTime(2026, 2, 17),
    );
    expect(
      service.toSolar(lunarYear: 2026, lunarMonth: 8, lunarDay: 15),
      DateTime(2026, 9, 25),
    );
  });
}
