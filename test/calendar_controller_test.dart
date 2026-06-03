import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/calendar/application/calendar_controller.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_repository.dart';
import 'package:zrk_calendar/features/todo/todo_repository.dart';
import 'package:zrk_calendar/services/festival_service.dart';
import 'package:zrk_calendar/services/json_import_export_service.dart';
import 'package:zrk_calendar/services/lunar_calendar_service.dart';
import 'package:zrk_calendar/services/official_holiday_service.dart';
import 'package:zrk_calendar/services/recurring_event_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late CalendarController controller;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final todoRepository = TodoRepository(database);
    final recurringEventRepository = RecurringEventRepository(database);
    final lunarService = LunarCalendarService();
    controller = CalendarController(
      todoRepository,
      recurringEventRepository,
      lunarService,
      FestivalService(lunarService),
      OfficialHolidayService(),
      RecurringEventService(lunarService),
      JsonImportExportService(recurringEventRepository),
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
  });

  test('控制器可以构建月视图日期格', () async {
    await controller.goToday();
    final days = controller.buildDays();
    expect(days.length % 7, 0);
    expect(days.length, inInclusiveRange(28, 42));
    expect(days.any((day) => day.isToday), isTrue);
    expect(days.first.lunarInfo.dayText, isNotEmpty);
  });

  test('月视图不生成不含本月日期的整行', () {
    controller.selectDate(DateTime(2026, 2, 17));
    final days = controller.buildDays();
    expect(days.length, 35);

    for (var row = 0; row < days.length ~/ 7; row++) {
      final week = days.skip(row * 7).take(7);
      expect(
        week.any((day) => day.date.year == 2026 && day.date.month == 2),
        isTrue,
      );
    }

    expect(days.first.date, DateTime(2026, 1, 26));
    expect(days.last.date, DateTime(2026, 3, 1));
  });

  test('2026 官方休班标记可以进入月视图数据', () async {
    controller.selectDate(DateTime(2026, 2, 17));
    final days = controller.buildDays();
    final springFestival = days.firstWhere(
      (day) =>
          day.date.year == 2026 && day.date.month == 2 && day.date.day == 17,
    );
    expect(
      springFestival.officialHoliday?.status,
      OfficialHolidayStatus.holiday,
    );

    final adjustedWorkday = days.firstWhere(
      (day) =>
          day.date.year == 2026 && day.date.month == 2 && day.date.day == 14,
    );
    expect(
      adjustedWorkday.officialHoliday?.status,
      OfficialHolidayStatus.adjustedWorkday,
    );
  });
}
