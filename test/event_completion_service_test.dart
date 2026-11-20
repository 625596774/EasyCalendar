import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/features/subscriptions/subscription_service.dart';
import 'package:zrk_calendar/services/event_completion_service.dart';

void main() {
  test('生日完成状态按具体日期保存并可取消', () async {
    final directory = await Directory.systemTemp.createTemp(
      'event-completion-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/event_completions.json');
    final service = EventCompletionService(file: file);
    addTearDown(service.dispose);
    await service.initialize();

    final thisYear = DateTime(2026, 8, 16);
    final nextYear = DateTime(2027, 8, 16);
    await service.setRecurringCompleted('birthday-id', thisYear, true);

    expect(service.isRecurringCompleted('birthday-id', thisYear), isTrue);
    expect(service.isRecurringCompleted('birthday-id', nextYear), isFalse);

    final reopened = EventCompletionService(file: file);
    addTearDown(reopened.dispose);
    await reopened.initialize();
    expect(reopened.isRecurringCompleted('birthday-id', thisYear), isTrue);

    await reopened.setRecurringCompleted('birthday-id', thisYear, false);
    expect(reopened.isRecurringCompleted('birthday-id', thisYear), isFalse);
  });

  test('订阅活动完成状态按来源、事件和日期区分', () async {
    final directory = await Directory.systemTemp.createTemp(
      'event-completion-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = EventCompletionService(
      file: File('${directory.path}/event_completions.json'),
    );
    addTearDown(service.dispose);
    await service.initialize();
    final source = CalendarSubscription(
      id: 'source-a',
      name: '课程',
      url: 'https://example.com/calendar',
      color: 0xFF2563EB,
    );
    final occurrence = SubscriptionOccurrence(
      source,
      SubscriptionEvent(
        key: 'event-a',
        title: '课程 A',
        start: DateTime.utc(2026, 11, 2, 9),
        end: DateTime.utc(2026, 11, 2, 10),
      ),
    );

    await service.setSubscriptionCompleted(
      occurrence,
      DateTime(2026, 11, 2),
      true,
    );

    expect(
      service.isSubscriptionCompleted(occurrence, DateTime(2026, 11, 2)),
      isTrue,
    );
    expect(
      service.isSubscriptionCompleted(occurrence, DateTime(2026, 11, 3)),
      isFalse,
    );
  });

  test('损坏的完成状态文件不会被覆盖', () async {
    final directory = await Directory.systemTemp.createTemp(
      'event-completion-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/event_completions.json');
    await file.writeAsString('broken');
    final service = EventCompletionService(file: file);
    addTearDown(service.dispose);

    await service.initialize();

    expect(service.storageError, isNotNull);
    expect(await file.readAsString(), 'broken');
    await expectLater(
      service.setRecurringCompleted('event', DateTime(2026, 11, 2), true),
      throwsFormatException,
    );
    expect(await file.readAsString(), 'broken');
  });
}
