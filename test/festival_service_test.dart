import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/services/festival_service.dart';
import 'package:zrk_calendar/services/lunar_calendar_service.dart';

void main() {
  final service = FestivalService(LunarCalendarService());

  test('农历节日判断', () {
    expect(service.festivalsFor(DateTime(2026, 2, 16)), contains('除夕'));
    expect(service.festivalsFor(DateTime(2026, 2, 17)), contains('春节'));
    expect(service.festivalsFor(DateTime(2026, 3, 3)), contains('元宵节'));
    expect(service.festivalsFor(DateTime(2026, 6, 19)), contains('端午节'));
    expect(service.festivalsFor(DateTime(2026, 8, 19)), contains('七夕'));
    expect(service.festivalsFor(DateTime(2026, 9, 25)), contains('中秋节'));
    expect(service.festivalsFor(DateTime(2026, 10, 18)), contains('重阳节'));
  });

  test('星期规则节日判断', () {
    expect(service.festivalsFor(DateTime(2026, 5, 10)), contains('母亲节'));
    expect(service.festivalsFor(DateTime(2026, 6, 21)), contains('父亲节'));
    expect(service.festivalsFor(DateTime(2026, 11, 26)), contains('感恩节'));
  });

  test('公历固定节日判断', () {
    expect(service.festivalsFor(DateTime(2026, 1, 1)), contains('元旦'));
    expect(service.festivalsFor(DateTime(2026, 12, 25)), contains('圣诞节'));
  });
}
