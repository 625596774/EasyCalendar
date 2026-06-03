import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/features/recurring_event/recurring_event_repository.dart';
import 'package:zrk_calendar/services/json_import_export_service.dart';

void main() {
  late AppDatabase database;
  late JsonImportExportService service;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    service = JsonImportExportService(RecurringEventRepository(database));
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
}
