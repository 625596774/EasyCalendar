import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/calendar/application/calendar_controller.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_repository.dart';
import 'package:zrk_calendar/features/todo/todo_repository.dart';
import 'package:zrk_calendar/services/daily_summary_service.dart';
import 'package:zrk_calendar/services/festival_service.dart';
import 'package:zrk_calendar/services/json_import_export_service.dart';
import 'package:zrk_calendar/services/lunar_calendar_service.dart';
import 'package:zrk_calendar/services/official_holiday_service.dart';
import 'package:zrk_calendar/services/recurring_event_service.dart';
import 'package:zrk_calendar/services/today_summary_export_service.dart';
import 'package:zrk_calendar/services/todo_completion_sound_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TodoRepository todoRepository;
  late CalendarController controller;
  late _FakeTodoCompletionSoundService todoCompletionSoundService;
  late Directory exportDirectory;
  late int localChangeNotifications;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    todoRepository = TodoRepository(database);
    final recurringEventRepository = RecurringEventRepository(database);
    final lunarService = LunarCalendarService();
    final festivalService = FestivalService(lunarService);
    final officialHolidayService = OfficialHolidayService();
    final recurringEventService = RecurringEventService(lunarService);
    final dailySummaryService = DailySummaryService(
      todoRepository: todoRepository,
      recurringEventRepository: recurringEventRepository,
      lunarCalendarService: lunarService,
      festivalService: festivalService,
      officialHolidayService: officialHolidayService,
      recurringEventService: recurringEventService,
    );
    exportDirectory = await Directory.systemTemp.createTemp(
      'zrk_calendar_controller_export_test_',
    );
    todoCompletionSoundService = _FakeTodoCompletionSoundService();
    localChangeNotifications = 0;
    controller = CalendarController(
      todoRepository,
      recurringEventRepository,
      lunarService,
      festivalService,
      officialHolidayService,
      recurringEventService,
      dailySummaryService,
      TodaySummaryExportService(
        dailySummaryService: dailySummaryService,
        directoryProvider: () async => exportDirectory,
      ),
      JsonImportExportService(recurringEventRepository),
      todoCompletionSoundService,
      onLocalDataChanged: () => localChangeNotifications += 1,
    );
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await database.close();
    if (await exportDirectory.exists()) {
      await _deleteDirectoryWithRetry(exportDirectory);
    }
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

  test('完成待办时播放提示音，取消完成不播放', () async {
    final date = controller.selectedDate;
    await todoRepository.addTodo(title: '泡一杯茶', date: date);
    final todo = (await todoRepository.getTodosForDate(date)).single;

    await controller.updateTodo(todo, isCompleted: true);
    expect(todoCompletionSoundService.playCount, 1);

    final completedTodo = (await todoRepository.getTodosForDate(date)).single;
    await controller.updateTodo(completedTodo, isCompleted: false);
    expect(todoCompletionSoundService.playCount, 1);
  });

  test('本地待办变更会通知自动同步调度', () async {
    await controller.addTodo('泡一杯茶');
    expect(localChangeNotifications, 1);

    final todo = (await todoRepository.getTodosForDate(
      controller.selectedDate,
    )).single;
    await controller.updateTodo(todo, title: '泡一壶茶');
    await controller.deleteTodo(todo);

    expect(localChangeNotifications, 3);
  });
}

class _FakeTodoCompletionSoundService extends TodoCompletionSoundService {
  int playCount = 0;

  @override
  void playCompleted() {
    playCount += 1;
  }
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return;
    } on FileSystemException {
      if (attempt == 2) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}
