import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_models.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_repository.dart';
import 'package:zrk_calendar/features/todo/todo_repository.dart';
import 'package:zrk_calendar/services/daily_summary_service.dart';
import 'package:zrk_calendar/services/festival_service.dart';
import 'package:zrk_calendar/services/lunar_calendar_service.dart';
import 'package:zrk_calendar/services/official_holiday_service.dart';
import 'package:zrk_calendar/services/recurring_event_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late TodoRepository todoRepository;
  late RecurringEventRepository recurringEventRepository;
  late DailySummaryService service;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    todoRepository = TodoRepository(database);
    recurringEventRepository = RecurringEventRepository(database);
    final lunarService = LunarCalendarService();
    service = DailySummaryService(
      todoRepository: todoRepository,
      recurringEventRepository: recurringEventRepository,
      lunarCalendarService: lunarService,
      festivalService: FestivalService(lunarService),
      officialHolidayService: OfficialHolidayService(),
      recurringEventService: RecurringEventService(lunarService),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('聚合某一天的农历、节日、休班、生日和待办摘要', () async {
    final date = DateTime(2026, 2, 17);
    await todoRepository.addTodo(
      title: '准备早餐',
      date: date,
      urgency: TodoUrgency.red,
      note: '买豆浆',
    );
    final completedId = await todoRepository.addTodo(title: '已经完成', date: date);
    await todoRepository.updateTodo(id: completedId, isCompleted: true);
    await recurringEventRepository.addEvent(
      title: '周年纪念',
      eventType: EventType.anniversary,
      calendarType: CalendarType.solar,
      month: 2,
      day: 17,
    );

    final summary = await service.buildForDate(
      date,
      generatedAt: DateTime.utc(2026, 2, 17, 1, 2, 3),
    );

    expect(summary.date, date);
    expect(summary.weekday, '星期二');
    expect(summary.lunarText, contains('正月初一'));
    expect(summary.festivals, contains('春节'));
    expect(summary.officialHolidayStatus?.name, '春节');
    expect(summary.officialHolidayStatus?.status, 'holiday');
    expect(summary.recurringEvents.single.title, '周年纪念');
    expect(summary.todos.map((todo) => todo.title), ['准备早餐', '已经完成']);
    expect(summary.todos.first.urgency, TodoUrgency.red);
    expect(summary.todos.last.isCompleted, isTrue);

    final encoded = jsonEncode(summary.toJson());
    expect(encoded, contains('"date":"2026-02-17"'));
    expect(encoded, contains('"generatedAt":"2026-02-17T01:02:03.000Z"'));
    expect(encoded, isNot(contains('syncStatus')));
    expect(encoded, isNot(contains('lastSyncedAt')));
    expect(encoded, isNot(contains('deletedAt')));
  });

  test('农历年尾生日可以匹配跨公历年份日期', () async {
    await recurringEventRepository.addEvent(
      title: '农历生日',
      eventType: EventType.birthday,
      calendarType: CalendarType.lunar,
      month: 12,
      day: 29,
    );

    final summary = await service.buildForDate(
      DateTime(2026, 2, 16),
      generatedAt: DateTime.utc(2026, 2, 16),
    );

    expect(
      summary.recurringEvents.map((event) => event.title),
      contains('农历生日'),
    );
  });
}
