import 'package:flutter/material.dart';
import 'package:zrk_calendar/app/app_scope.dart';
import 'package:zrk_calendar/features/calendar/presentation/calendar_page.dart';
import 'package:zrk_calendar/features/subscriptions/subscription_service.dart';
import 'package:zrk_calendar/services/sync/noop_sync_service.dart';
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
  late TodoCompletionSoundService todoCompletionSoundService;
  late SubscriptionService subscriptions;
  late Directory exportDirectory;
  late int localChangeNotifications;

  Future<void> setup() async {
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
    todoCompletionSoundService = const TodoCompletionSoundService();
    subscriptions = SubscriptionService(
      file: File('${exportDirectory.path}/subscriptions.json'),
      fetcher: (_) async =>
          'BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\nUID:course\nDTSTART:20260909T070000Z\nDTEND:20260909T095000Z\nSUMMARY:Example course\nLOCATION:Room 1\nEND:VEVENT\nEND:VCALENDAR',
    );
    await subscriptions.initialize();
    await subscriptions.add(
      'HKU',
      await subscriptions.preview('https://example.com/calendar'),
    );
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
      subscriptions: subscriptions,
      onLocalDataChanged: () => localChangeNotifications += 1,
    );
    await controller.initialize();
    for (var i = 0; i < 12; i++) {
      await todoRepository.addTodo(
        title: 'Todo $i',
        date: DateTime(2026, 9, 9),
      );
    }
  }

  Future<void> cleanup() async {
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await database.close();
    if (await exportDirectory.exists()) {
      await exportDirectory.delete(recursive: true);
    }
  }

  for (final width in [1400.0, 1100.0, 390.0]) {
    testWidgets('subscription calendar layout at $width pixels', (
      tester,
    ) async {
      await tester.runAsync(setup);
      addTearDown(() => tester.runAsync(cleanup));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        controller.selectDate(DateTime(2026, 9, 9));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpWidget(
        AppScope(
          controller: controller,
          syncService: NoopSyncService(),
          child: MaterialApp(home: const CalendarPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        controller.buildDays().where((d) => d.subscriptionEvents.isNotEmpty),
        isNotEmpty,
      );
      if (width < 700) {
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('日历订阅').first);
      await tester.pumpAndSettle();
      expect(find.text('HKU'), findsOneWidget);
      expect(find.text('1 条日程 · 显示中'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('添加订阅'));
      await tester.pumpAndSettle();
      expect(find.text('读取预览'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
