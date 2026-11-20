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
import 'package:zrk_calendar/features/recurring_event/recurring_event_models.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_repository.dart';
import 'package:zrk_calendar/features/todo/todo_repository.dart';
import 'package:zrk_calendar/services/daily_summary_service.dart';
import 'package:zrk_calendar/services/event_completion_service.dart';
import 'package:zrk_calendar/services/festival_service.dart';
import 'package:zrk_calendar/services/json_import_export_service.dart';
import 'package:zrk_calendar/services/lunar_calendar_service.dart';
import 'package:zrk_calendar/services/official_holiday_service.dart';
import 'package:zrk_calendar/services/recurring_event_service.dart';
import 'package:zrk_calendar/services/today_summary_export_service.dart';
import 'package:zrk_calendar/services/todo_attachment_service.dart';
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
          'BEGIN:VCALENDAR\nVERSION:2.0\n'
          'BEGIN:VEVENT\nUID:course-a\nDTSTART:20260909T010000Z\nDTEND:20260909T020000Z\nSUMMARY:Course A\nEND:VEVENT\n'
          'BEGIN:VEVENT\nUID:course-b\nDTSTART:20260909T030000Z\nDTEND:20260909T040000Z\nSUMMARY:Course B\nEND:VEVENT\n'
          'BEGIN:VEVENT\nUID:assignment\nDTSTART:20260909T100000Z\nDTEND:20260909T110000Z\nSUMMARY:Assignment due\nEND:VEVENT\n'
          'END:VCALENDAR',
    );
    await subscriptions.initialize();
    await subscriptions.add(
      'HKU',
      await subscriptions.preview('https://example.com/calendar'),
    );
    await recurringEventRepository.addEvent(
      title: 'Test anniversary',
      eventType: EventType.anniversary,
      calendarType: CalendarType.solar,
      month: 9,
      day: 9,
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
      eventCompletions: EventCompletionService(
        file: File('${exportDirectory.path}/event_completions.json'),
      ),
      todoAttachments: TodoAttachmentService(rootDirectory: exportDirectory),
      onLocalDataChanged: () => localChangeNotifications += 1,
    );
    await controller.initialize();
    for (var i = 0; i < 12; i++) {
      await todoRepository.addTodo(
        title: 'Todo $i',
        date: DateTime(2026, 9, 9),
      );
    }
    await todoRepository.addTodo(
      title: '跨日搜索目标',
      date: DateTime(2026, 10, 1),
      note: '关键词在备注里也能找到',
    );
    await todoRepository.addTodo(title: '未完成格子上方', date: DateTime(2026, 10, 2));
    final completedCellTodoId = await todoRepository.addTodo(
      title: '已完成格子底部',
      date: DateTime(2026, 10, 2),
    );
    await todoRepository.updateTodo(id: completedCellTodoId, isCompleted: true);
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
      expect(find.text('09:00 Course A'), findsOneWidget);
      expect(find.text('11:00 Course B'), findsOneWidget);
      expect(find.text('18:00 Assignment due'), findsOneWidget);
      if (width >= 700) {
        await tester.tap(find.byTooltip('添加待办'));
        await tester.pumpAndSettle();
        expect(find.text('添加照片'), findsOneWidget);
        expect(find.text('照片仅保存在本机，不参与云同步。'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        final occurrence = subscriptions.eventsOn(DateTime(2026, 9, 9)).first;
        await tester.tap(find.byType(Checkbox).first);
        await tester.pumpAndSettle();
        expect(
          controller.isSubscriptionCompleted(occurrence, DateTime(2026, 9, 9)),
          isTrue,
        );
        expect(
          tester.widget<Text>(find.text('09:00 Course A')).style?.decoration,
          TextDecoration.lineThrough,
        );

        final anniversaryChip = find.ancestor(
          of: find.text('Test anniversary'),
          matching: find.byType(FilterChip),
        );
        expect(anniversaryChip, findsOneWidget);
        await tester.tap(anniversaryChip);
        await tester.pumpAndSettle();
        expect(tester.widget<FilterChip>(anniversaryChip).selected, isTrue);

        if (width == 1400) {
          await tester.tap(find.byTooltip('搜索待办和日历'));
          await tester.pumpAndSettle();
          expect(find.text('搜索待办与导入日历'), findsOneWidget);
          await tester.enterText(find.byType(TextField), '跨日搜索');
          await tester.pumpAndSettle();
          final searchResult = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('跨日搜索目标'),
          );
          expect(searchResult, findsOneWidget);
          expect(find.textContaining('2026-10-01'), findsOneWidget);
          await tester.tap(searchResult);
          await tester.pumpAndSettle();
          expect(controller.selectedDate, DateTime(2026, 10, 1));

          await tester.tap(find.byTooltip('搜索待办和日历'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'Course A');
          await tester.pumpAndSettle();
          final calendarResult = find.descendant(
            of: find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(ListTile),
            ),
            matching: find.textContaining('Course A'),
          );
          expect(find.text('导入日历（1）'), findsOneWidget);
          expect(calendarResult, findsOneWidget);
          await tester.tap(calendarResult);
          await tester.pumpAndSettle();
          expect(controller.selectedDate, DateTime(2026, 9, 9));

          controller.selectDate(DateTime(2026, 10, 2));
          await tester.pumpAndSettle();
          final octoberSecondCell = find.byKey(const ValueKey('2026-10-02'));
          final incompleteCellTodo = find.descendant(
            of: octoberSecondCell,
            matching: find.text('未完成格子上方'),
          );
          final completedCellTodo = find.descendant(
            of: octoberSecondCell,
            matching: find.text('已完成格子底部'),
          );
          expect(incompleteCellTodo, findsOneWidget);
          expect(completedCellTodo, findsOneWidget);
          expect(
            tester.getTopLeft(completedCellTodo).dy,
            greaterThan(tester.getTopLeft(incompleteCellTodo).dy),
          );

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          await tester.tap(find.byTooltip('回到今天的待办'));
          await tester.pumpAndSettle();
          expect(controller.selectedDate, today);
          expect(
            controller.buildDays().singleWhere((day) => day.isToday).isSelected,
            isTrue,
          );
        }
      }
      if (width < 700) {
        await tester.tap(find.byTooltip('更多'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('日历订阅').first);
      await tester.pumpAndSettle();
      expect(find.text('HKU'), findsWidgets);
      expect(find.text('3 条日程 · 显示中'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('添加订阅'));
      await tester.pumpAndSettle();
      expect(find.text('读取预览'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
