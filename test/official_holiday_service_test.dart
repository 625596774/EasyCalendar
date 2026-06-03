import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/services/official_holiday_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('官方假日 JSON 加载', () async {
    final service = OfficialHolidayService();
    await service.loadYear(2026);

    final springHoliday = service.getForDate(DateTime(2026, 2, 17));
    expect(springHoliday?.name, '春节');
    expect(springHoliday?.status, OfficialHolidayStatus.holiday);

    final adjustedWorkday = service.getForDate(DateTime(2026, 2, 14));
    expect(adjustedWorkday?.name, '春节');
    expect(adjustedWorkday?.status, OfficialHolidayStatus.adjustedWorkday);
  });
}
