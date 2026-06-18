import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/features/calendar/domain/daily_summary.dart';
import 'package:zrk_calendar/services/daily_summary_service.dart';
import 'package:zrk_calendar/services/today_summary_export_service.dart';

void main() {
  late Directory directory;
  late DailySummary summary;
  late _FakeDailySummaryService dailySummaryService;
  late TodaySummaryExportService service;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'zrk_calendar_today_summary_export_test_',
    );
    summary = _summary();
    dailySummaryService = _FakeDailySummaryService(summary);
    service = TodaySummaryExportService(
      dailySummaryService: dailySummaryService,
      directoryProvider: () async => directory,
    );
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('可以写出 today_summary.json', () async {
    final result = await service.exportSummary(summary);

    expect(result.isSuccess, isTrue);
    expect(result.path, isNotNull);
    expect(result.path, endsWith(TodaySummaryExportService.fileName));

    final file = File(result.path!);
    expect(await file.exists(), isTrue);
    final decoded =
        jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    expect(decoded['date'], '2026-06-10');
    expect(decoded['weekday'], '星期三');
    expect(decoded['lunarText'], '四月廿五');
    expect(decoded['generatedAt'], '2026-06-10T01:02:03.000Z');

    final todos = decoded['todos'] as List<dynamic>;
    expect(todos, hasLength(1));
    expect(todos.single, {
      'id': 'todo-1',
      'title': '写测试',
      'isCompleted': false,
      'urgency': 'red',
    });
  });

  test('默认导出今天摘要', () async {
    final now = DateTime(2026, 6, 10, 8, 30);
    final result = await service.exportToday(now: now);

    expect(result.isSuccess, isTrue);
    expect(dailySummaryService.lastDate, now);
    expect(await File(result.path!).exists(), isTrue);
  });

  test('写入前会创建目标文件的父目录', () async {
    final result = await service.exportSummary(
      summary,
      outputFileName: 'nested/today_summary.json',
    );

    expect(result.isSuccess, isTrue);
    expect(await File(result.path!).exists(), isTrue);
  });

  test('并发导出不会互相抢占临时文件', () async {
    final results = await Future.wait([
      for (var index = 0; index < 8; index++) service.exportSummary(summary),
    ]);

    expect(results.every((result) => result.isSuccess), isTrue);
    expect(await File(results.last.path!).exists(), isTrue);
  });

  test('导出的 JSON 不包含内部同步和用户身份字段', () async {
    final result = await service.exportSummary(summary);
    final raw = await File(result.path!).readAsString();

    expect(raw, isNot(contains('sync_status')));
    expect(raw, isNot(contains('syncStatus')));
    expect(raw, isNot(contains('last_synced_at')));
    expect(raw, isNot(contains('lastSyncedAt')));
    expect(raw, isNot(contains('user_id')));
    expect(raw, isNot(contains('service_role')));
    expect(raw, isNot(contains('SUPABASE')));
    expect(raw, isNot(contains('不要导出这段备注')));
  });

  test('导出失败返回失败结果且不抛出', () async {
    final failingService = TodaySummaryExportService(
      dailySummaryService: dailySummaryService,
      directoryProvider: () async => throw FileSystemException('denied'),
    );

    final result = await failingService.exportSummary(summary);

    expect(result.isSuccess, isFalse);
    expect(result.path, isNull);
    expect(result.error, 'FileSystemException');
  });
}

DailySummary _summary() {
  return DailySummary(
    date: DateTime(2026, 6, 10),
    weekday: '星期三',
    lunarText: '四月廿五',
    festivals: const ['测试节日'],
    officialHolidayStatus: null,
    recurringEvents: const [
      DailyRecurringEventSummary(
        id: 'event-1',
        title: '纪念日',
        eventType: 'anniversary',
        eventTypeLabel: '纪念日',
        calendarType: 'solar',
        calendarTypeLabel: '公历',
        note: '不要导出这段备注',
      ),
    ],
    todos: const [
      DailyTodoSummary(
        id: 'todo-1',
        title: '写测试',
        isCompleted: false,
        urgency: 'red',
        note: '不要导出这段备注',
      ),
    ],
    generatedAt: DateTime.utc(2026, 6, 10, 1, 2, 3),
  );
}

class _FakeDailySummaryService implements DailySummaryService {
  _FakeDailySummaryService(this.summary);

  final DailySummary summary;
  DateTime? lastDate;

  @override
  Future<DailySummary> buildForDate(DateTime date, {DateTime? generatedAt}) {
    lastDate = date;
    return Future.value(summary);
  }
}
