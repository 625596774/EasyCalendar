import '../../database/app_database.dart';

abstract final class SyncRecordStatus {
  static const pending = 'pending';
  static const synced = 'synced';
  static const failed = 'failed';
}

enum SyncMergeDecision { useLocal, useRemote }

SyncMergeDecision chooseUpdatedAtWinner({
  required DateTime localUpdatedAt,
  required DateTime remoteUpdatedAt,
}) {
  return remoteUpdatedAt.toUtc().isAfter(localUpdatedAt.toUtc())
      ? SyncMergeDecision.useRemote
      : SyncMergeDecision.useLocal;
}

class TodoSyncRecord {
  const TodoSyncRecord({
    required this.id,
    required this.title,
    required this.date,
    required this.isCompleted,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String title;
  final DateTime date;
  final bool isCompleted;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory TodoSyncRecord.fromTodoItem(TodoItem item) {
    return TodoSyncRecord(
      id: item.id,
      title: item.title,
      date: _dateOnly(item.date),
      isCompleted: item.isCompleted,
      note: item.note,
      createdAt: item.createdAt.toUtc(),
      updatedAt: item.updatedAt.toUtc(),
      deletedAt: item.deletedAt?.toUtc(),
    );
  }

  factory TodoSyncRecord.fromSupabaseRow(Map<String, dynamic> row) {
    return TodoSyncRecord(
      id: _readString(row, 'id'),
      title: _readString(row, 'title'),
      date: parseSupabaseDate(row['date']),
      isCompleted: _readBool(row, 'is_completed'),
      note: row['note'] as String?,
      createdAt: parseSupabaseTimestamp(row['created_at']),
      updatedAt: parseSupabaseTimestamp(row['updated_at']),
      deletedAt: parseNullableSupabaseTimestamp(row['deleted_at']),
    );
  }

  Map<String, Object?> toSupabasePayload({required String userId}) {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'date': formatSupabaseDate(date),
      'is_completed': isCompleted,
      'note': note,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }
}

class RecurringEventSyncRecord {
  const RecurringEventSyncRecord({
    required this.id,
    required this.title,
    required this.eventType,
    required this.calendarType,
    required this.month,
    required this.day,
    required this.isLeapMonth,
    required this.leapMonthPolicy,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.note,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String eventType;
  final String calendarType;
  final int month;
  final int day;
  final bool isLeapMonth;
  final String leapMonthPolicy;
  final String? note;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  factory RecurringEventSyncRecord.fromRecurringEvent(RecurringEvent event) {
    return RecurringEventSyncRecord(
      id: event.id,
      title: event.title,
      eventType: event.eventType,
      calendarType: event.calendarType,
      month: event.month,
      day: event.day,
      isLeapMonth: event.isLeapMonth,
      leapMonthPolicy: event.leapMonthPolicy,
      note: event.note,
      enabled: event.enabled,
      createdAt: event.createdAt.toUtc(),
      updatedAt: event.updatedAt.toUtc(),
      deletedAt: event.deletedAt?.toUtc(),
    );
  }

  factory RecurringEventSyncRecord.fromSupabaseRow(Map<String, dynamic> row) {
    return RecurringEventSyncRecord(
      id: _readString(row, 'id'),
      title: _readString(row, 'title'),
      eventType: _readString(row, 'event_type'),
      calendarType: _readString(row, 'calendar_type'),
      month: _readInt(row, 'month'),
      day: _readInt(row, 'day'),
      isLeapMonth: _readBool(row, 'is_leap_month'),
      leapMonthPolicy: _readString(row, 'leap_month_policy'),
      note: row['note'] as String?,
      enabled: _readBool(row, 'enabled'),
      createdAt: parseSupabaseTimestamp(row['created_at']),
      updatedAt: parseSupabaseTimestamp(row['updated_at']),
      deletedAt: parseNullableSupabaseTimestamp(row['deleted_at']),
    );
  }

  Map<String, Object?> toSupabasePayload({required String userId}) {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'event_type': eventType,
      'calendar_type': calendarType,
      'month': month,
      'day': day,
      'is_leap_month': isLeapMonth,
      'leap_month_policy': leapMonthPolicy,
      'note': note,
      'enabled': enabled,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
      'deleted_at': deletedAt?.toUtc().toIso8601String(),
    };
  }
}

String formatSupabaseDate(DateTime date) {
  final normalized = _dateOnly(date);
  return '${normalized.year.toString().padLeft(4, '0')}-'
      '${normalized.month.toString().padLeft(2, '0')}-'
      '${normalized.day.toString().padLeft(2, '0')}';
}

DateTime parseSupabaseDate(Object? value) {
  if (value is DateTime) {
    return _dateOnly(value);
  }
  if (value is String && value.isNotEmpty) {
    final parts = value.split('-');
    if (parts.length >= 3) {
      return DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2].substring(0, 2)),
      );
    }
  }
  throw FormatException('无法解析云端日期：$value');
}

DateTime parseSupabaseTimestamp(Object? value) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.parse(value).toUtc();
  }
  throw FormatException('无法解析云端时间：$value');
}

DateTime? parseNullableSupabaseTimestamp(Object? value) {
  if (value == null) {
    return null;
  }
  return parseSupabaseTimestamp(value);
}

DateTime _dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

String _readString(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is String) {
    return value;
  }
  throw FormatException('云端字段 $key 不是字符串。');
}

int _readInt(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('云端字段 $key 不是整数。');
}

bool _readBool(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is bool) {
    return value;
  }
  throw FormatException('云端字段 $key 不是布尔值。');
}
