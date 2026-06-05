import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_models.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_repository.dart';
import 'package:zrk_calendar/services/json_import_export_service.dart';

void main() {
  late AppDatabase database;
  late RecurringEventRepository repository;
  late JsonImportExportService service;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = RecurringEventRepository(database);
    service = JsonImportExportService(repository);
  });

  tearDown(() async {
    await database.close();
  });

  test('合法 JSON 可以解析生日和纪念日规则', () {
    final parsed = service.parseRules('''
{
  "schemaVersion": 1,
  "rules": [
    {
      "title": "妈妈生日",
      "eventType": "birthday",
      "calendarType": "solar",
      "month": 8,
      "day": 16,
      "isLeapMonth": false,
      "leapMonthPolicy": "useNormalMonth",
      "enabled": true,
      "note": "每年提醒"
    },
    {
      "title": "奶奶生日",
      "eventType": "birthday",
      "calendarType": "lunar",
      "month": 8,
      "day": 15,
      "isLeapMonth": false,
      "leapMonthPolicy": "useNormalMonth",
      "enabled": true
    }
  ]
}
''');
    expect(parsed.errors, isEmpty);
    expect(parsed.rules, hasLength(2));
  });

  test('非法 JSON 返回用户可读错误', () {
    final parsed = service.parseRules('''
{
  "rules": [
    {
      "title": "",
      "eventType": "wrong",
      "calendarType": "solar",
      "month": 13,
      "day": 1
    }
  ]
}
''');
    expect(parsed.rules, isEmpty);
    expect(parsed.errors.single, contains('标题'));
  });

  test('格式错误 JSON 不崩溃', () {
    final parsed = service.parseRules('{ bad json');
    expect(parsed.rules, isEmpty);
    expect(parsed.errors.single, contains('JSON 格式无效'));
  });

  test('导入 JSON 后生成 UUID 且标记 pending', () async {
    final directory = await Directory.systemTemp.createTemp(
      'zrk_calendar_json_import_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });
    final file = File('${directory.path}/rules.json');
    await file.writeAsString('''
{
  "schemaVersion": 1,
  "rules": [
    {
      "title": "奶奶生日",
      "eventType": "birthday",
      "calendarType": "lunar",
      "month": 8,
      "day": 15,
      "isLeapMonth": false,
      "leapMonthPolicy": "useNormalMonth",
      "enabled": true
    }
  ]
}
''');

    final result = await service.importFromFile(file.path);
    expect(result.importedCount, 1);
    expect(result.errors, isEmpty);

    final events = await repository.getEvents();
    expect(events, hasLength(1));
    expect(events.single.id, matches(_uuidPattern));
    expect(
      events.single.syncStatus,
      RecurringEventRepository.pendingSyncStatus,
    );
    expect(events.single.deletedAt, isNull);
    expect(events.single.lastSyncedAt, isNull);
  });

  test('导出 JSON 不包含内部同步字段且跳过软删除记录', () async {
    final activeId = await repository.addEvent(
      title: '妈妈生日',
      eventType: EventType.birthday,
      calendarType: CalendarType.solar,
      month: 8,
      day: 16,
    );
    final deletedId = await repository.addEvent(
      title: '旧纪念日',
      eventType: EventType.anniversary,
      calendarType: CalendarType.solar,
      month: 1,
      day: 2,
    );
    await repository.deleteEvent(deletedId);

    final events = await repository.getEventsIncludingDeleted();
    final exported = service.exportJson(events);
    expect(exported, isNot(contains('syncStatus')));
    expect(exported, isNot(contains('sync_status')));
    expect(exported, isNot(contains('deletedAt')));
    expect(exported, isNot(contains('deleted_at')));
    expect(exported, isNot(contains('lastSyncedAt')));
    expect(exported, isNot(contains('last_synced_at')));

    final decoded = jsonDecode(exported) as Map<String, dynamic>;
    final rules = decoded['rules'] as List<dynamic>;
    expect(rules, hasLength(1));
    expect((rules.single as Map<String, dynamic>)['title'], '妈妈生日');
    expect(events.map((event) => event.id), contains(activeId));
  });
}

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
