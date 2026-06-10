import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zrk_calendar/database/app_database.dart';
import 'package:zrk_calendar/services/sync/supabase_bootstrap.dart';
import 'package:zrk_calendar/services/sync/sync_models.dart';
import 'package:zrk_calendar/services/sync/supabase_sync_service.dart';

void main() {
  test('本地 pending todo 能被转换为云端 payload', () {
    final todo = TodoItem(
      id: '11111111-1111-4111-8111-111111111111',
      title: '同步待办',
      date: DateTime(2026, 6, 5, 12),
      isCompleted: false,
      note: '备注',
      createdAt: DateTime.utc(2026, 6, 5, 1),
      updatedAt: DateTime.utc(2026, 6, 5, 2),
      deletedAt: null,
      syncStatus: SyncRecordStatus.pending,
      lastSyncedAt: null,
    );

    final payload = TodoSyncRecord.fromTodoItem(
      todo,
    ).toSupabasePayload(userId: 'user-1');

    expect(payload['id'], todo.id);
    expect(payload['user_id'], 'user-1');
    expect(payload['date'], '2026-06-05');
    expect(payload['is_completed'], isFalse);
    expect(payload, isNot(contains('sync_status')));
    expect(payload, isNot(contains('last_synced_at')));
  });

  test('云端 todo row 能转换为本地 upsert 数据', () {
    final record = TodoSyncRecord.fromSupabaseRow({
      'id': '22222222-2222-4222-8222-222222222222',
      'title': '云端待办',
      'date': '2026-06-06',
      'is_completed': true,
      'note': null,
      'created_at': '2026-06-05T01:00:00Z',
      'updated_at': '2026-06-05T02:00:00Z',
      'deleted_at': null,
    });

    expect(record.date, DateTime(2026, 6, 6));
    expect(record.isCompleted, isTrue);
    expect(record.updatedAt, DateTime.utc(2026, 6, 5, 2));
  });

  test('pending recurring event 能被转换为云端 payload', () {
    final event = RecurringEvent(
      id: '33333333-3333-4333-8333-333333333333',
      title: '生日',
      eventType: 'birthday',
      calendarType: 'lunar',
      month: 8,
      day: 15,
      isLeapMonth: false,
      leapMonthPolicy: 'useNormalMonth',
      note: null,
      enabled: true,
      createdAt: DateTime.utc(2026, 6, 5, 1),
      updatedAt: DateTime.utc(2026, 6, 5, 2),
      deletedAt: null,
      syncStatus: SyncRecordStatus.pending,
      lastSyncedAt: null,
    );

    final payload = RecurringEventSyncRecord.fromRecurringEvent(
      event,
    ).toSupabasePayload(userId: 'user-1');

    expect(payload['id'], event.id);
    expect(payload['user_id'], 'user-1');
    expect(payload['event_type'], 'birthday');
    expect(payload['calendar_type'], 'lunar');
    expect(payload, isNot(contains('sync_status')));
  });

  test('云端 recurring event row 能转换为本地 upsert 数据', () {
    final record = RecurringEventSyncRecord.fromSupabaseRow({
      'id': '44444444-4444-4444-8444-444444444444',
      'title': '纪念日',
      'event_type': 'anniversary',
      'calendar_type': 'solar',
      'month': 10,
      'day': 1,
      'is_leap_month': false,
      'leap_month_policy': 'useNormalMonth',
      'note': '云端',
      'enabled': false,
      'created_at': '2026-06-05T01:00:00Z',
      'updated_at': '2026-06-05T02:00:00Z',
      'deleted_at': null,
    });

    expect(record.title, '纪念日');
    expect(record.enabled, isFalse);
    expect(record.updatedAt, DateTime.utc(2026, 6, 5, 2));
  });

  test('updated_at 后写 wins 合并逻辑', () {
    expect(
      chooseUpdatedAtWinner(
        localUpdatedAt: DateTime.utc(2026, 6, 5, 2),
        remoteUpdatedAt: DateTime.utc(2026, 6, 5, 3),
      ),
      SyncMergeDecision.useRemote,
    );
    expect(
      chooseUpdatedAtWinner(
        localUpdatedAt: DateTime.utc(2026, 6, 5, 4),
        remoteUpdatedAt: DateTime.utc(2026, 6, 5, 3),
      ),
      SyncMergeDecision.useLocal,
    );
  });

  test('deleted_at 软删除同步逻辑', () {
    final deletedAt = DateTime.utc(2026, 6, 5, 3);
    final record = TodoSyncRecord.fromSupabaseRow({
      'id': '55555555-5555-4555-8555-555555555555',
      'title': '已删除',
      'date': '2026-06-05',
      'is_completed': false,
      'note': null,
      'created_at': '2026-06-05T01:00:00Z',
      'updated_at': '2026-06-05T04:00:00Z',
      'deleted_at': deletedAt.toIso8601String(),
    });

    expect(record.deletedAt, deletedAt);
  });

  test('未配置 Supabase 时 bootstrap 返回本地模式', () async {
    final directory = await Directory.systemTemp.createTemp(
      'zrk_calendar_no_env_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final result = await initializeSupabaseFromDotEnv(
      fileName: '${directory.path}/missing.env',
    );

    expect(result.isConfigured, isFalse);
    expect(result.client, isNull);
  });

  test('Supabase dart define 为空时仍回退到本地模式', () async {
    final directory = await Directory.systemTemp.createTemp(
      'zrk_calendar_empty_define_test_',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final result = await initializeSupabaseFromDotEnv(
      fileName: '${directory.path}/missing.env',
      defineProvider: (_) => '  ',
    );

    expect(result.isConfigured, isFalse);
    expect(result.client, isNull);
  });

  test('同步失败详情保留 PostgREST code 和 message', () {
    final details = safeSyncErrorDetails(
      const PostgrestException(
        message: 'permission denied for table todo_items',
        code: '42501',
      ),
    );

    expect(
      details,
      'PostgrestException / 42501 / permission denied for table todo_items',
    );
  });

  test('同步失败详情会脱敏 URL、邮箱、UUID 和长 token', () {
    final details = safeSyncErrorDetails(
      const PostgrestException(
        message:
            'request https://example.supabase.co/rest/v1/todo_items failed '
            'for test@example.com id '
            '11111111-1111-4111-8111-111111111111 token '
            'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        code: 'PGRST301',
      ),
    );

    expect(details, contains('PostgrestException / PGRST301'));
    expect(details, contains('[url]'));
    expect(details, contains('[email]'));
    expect(details, contains('[id]'));
    expect(details, contains('[redacted]'));
    expect(details, isNot(contains('example.supabase.co')));
    expect(details, isNot(contains('test@example.com')));
    expect(details, isNot(contains('11111111-1111-4111-8111-111111111111')));
  });
}
