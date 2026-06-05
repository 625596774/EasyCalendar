import 'dart:convert';
import 'dart:io';

import '../database/app_database.dart';
import '../features/recurring_event/recurring_event_models.dart';
import '../features/recurring_event/recurring_event_repository.dart';

class ImportResult {
  const ImportResult({required this.importedCount, required this.errors});

  final int importedCount;
  final List<String> errors;

  bool get hasErrors => errors.isNotEmpty;
}

class ParsedRecurringEventRule {
  const ParsedRecurringEventRule({
    required this.title,
    required this.eventType,
    required this.calendarType,
    required this.month,
    required this.day,
    required this.isLeapMonth,
    required this.leapMonthPolicy,
    required this.enabled,
    this.note,
  });

  final String title;
  final EventType eventType;
  final CalendarType calendarType;
  final int month;
  final int day;
  final bool isLeapMonth;
  final LeapMonthPolicy leapMonthPolicy;
  final bool enabled;
  final String? note;
}

class JsonImportExportService {
  JsonImportExportService(this._repository);

  final RecurringEventRepository _repository;

  Future<ImportResult> importFromFile(String path) async {
    final file = File(path);
    final raw = await file.readAsString();
    final parsed = parseRules(raw);
    var importedCount = 0;
    for (final rule in parsed.rules) {
      await _repository.addEvent(
        title: rule.title,
        eventType: rule.eventType,
        calendarType: rule.calendarType,
        month: rule.month,
        day: rule.day,
        isLeapMonth: rule.isLeapMonth,
        leapMonthPolicy: rule.leapMonthPolicy,
        note: rule.note,
        enabled: rule.enabled,
      );
      importedCount++;
    }
    return ImportResult(importedCount: importedCount, errors: parsed.errors);
  }

  ParsedRuleSet parseRules(String raw) {
    final errors = <String>[];
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const ParsedRuleSet(rules: [], errors: ['JSON 格式无效，无法解析。']);
    }
    if (decoded is! Map<String, dynamic>) {
      return const ParsedRuleSet(rules: [], errors: ['JSON 顶层必须是对象。']);
    }
    final rulesJson = decoded['rules'];
    if (rulesJson is! List) {
      return const ParsedRuleSet(rules: [], errors: ['缺少 rules 数组。']);
    }

    final rules = <ParsedRecurringEventRule>[];
    for (var i = 0; i < rulesJson.length; i++) {
      final index = i + 1;
      final item = rulesJson[i];
      if (item is! Map<String, dynamic>) {
        errors.add('第 $index 项不是对象。');
        continue;
      }
      final title = _stringField(item, 'title');
      final eventTypeRaw = _stringField(item, 'eventType');
      final calendarTypeRaw = _stringField(item, 'calendarType');
      final month = item['month'];
      final day = item['day'];
      final isLeapMonth = item['isLeapMonth'] ?? false;
      final leapMonthPolicyRaw =
          item['leapMonthPolicy'] as String? ??
          LeapMonthPolicy.useNormalMonth.value;
      final enabled = item['enabled'] ?? true;
      final note = item['note'];

      if (title == null || title.trim().isEmpty) {
        errors.add('第 $index 项缺少标题 title。');
        continue;
      }
      final eventType = EventType.values
          .where((type) => type.value == eventTypeRaw)
          .firstOrNull;
      if (eventType == null) {
        errors.add('第 $index 项 eventType 必须是 birthday 或 anniversary。');
        continue;
      }
      final calendarType = CalendarType.values
          .where((type) => type.value == calendarTypeRaw)
          .firstOrNull;
      if (calendarType == null) {
        errors.add('第 $index 项 calendarType 必须是 solar 或 lunar。');
        continue;
      }
      final leapMonthPolicy = LeapMonthPolicy.values
          .where((policy) => policy.value == leapMonthPolicyRaw)
          .firstOrNull;
      if (leapMonthPolicy == null) {
        errors.add('第 $index 项 leapMonthPolicy 不受支持。');
        continue;
      }
      if (month is! int || month < 1 || month > 12) {
        errors.add('第 $index 项 month 必须是 1 到 12 的整数。');
        continue;
      }
      if (day is! int || day < 1 || day > 31) {
        errors.add('第 $index 项 day 必须是 1 到 31 的整数。');
        continue;
      }
      if (isLeapMonth is! bool) {
        errors.add('第 $index 项 isLeapMonth 必须是布尔值。');
        continue;
      }
      if (enabled is! bool) {
        errors.add('第 $index 项 enabled 必须是布尔值。');
        continue;
      }
      if (note != null && note is! String) {
        errors.add('第 $index 项 note 必须是字符串。');
        continue;
      }
      if (calendarType == CalendarType.solar && isLeapMonth) {
        errors.add('第 $index 项公历事件不能设置 isLeapMonth。');
        continue;
      }

      rules.add(
        ParsedRecurringEventRule(
          title: title.trim(),
          eventType: eventType,
          calendarType: calendarType,
          month: month,
          day: day,
          isLeapMonth: isLeapMonth,
          leapMonthPolicy: leapMonthPolicy,
          enabled: enabled,
          note: note?.trim().isEmpty ?? true ? null : note.trim(),
        ),
      );
    }
    return ParsedRuleSet(rules: rules, errors: errors);
  }

  Future<void> exportToFile(String path) async {
    final events = await _repository.getEvents();
    final data = exportJson(events);
    await File(path).writeAsString(data);
  }

  String exportJson(List<RecurringEvent> events) {
    final payload = {
      'schemaVersion': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'rules': events
          .where((event) => event.deletedAt == null)
          .map(_eventToJson)
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Map<String, Object?> _eventToJson(RecurringEvent event) {
    return {
      'title': event.title,
      'eventType': event.eventType,
      'calendarType': event.calendarType,
      'month': event.month,
      'day': event.day,
      'isLeapMonth': event.isLeapMonth,
      'leapMonthPolicy': event.leapMonthPolicy,
      'enabled': event.enabled,
      'note': event.note,
    };
  }

  String? _stringField(Map<String, dynamic> item, String key) {
    final value = item[key];
    return value is String ? value : null;
  }
}

class ParsedRuleSet {
  const ParsedRuleSet({required this.rules, required this.errors});

  final List<ParsedRecurringEventRule> rules;
  final List<String> errors;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) {
      return null;
    }
    return iterator.current;
  }
}
