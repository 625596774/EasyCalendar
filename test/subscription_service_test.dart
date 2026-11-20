import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/features/subscriptions/subscription_service.dart';

String feed(String body) =>
    'BEGIN:VCALENDAR\r\nVERSION:2.0\r\n$body\r\nEND:VCALENDAR';
String event({
  String uid = 'a',
  String title = 'Course',
  String start = '20260909T070000Z',
  String extra = '',
}) =>
    'BEGIN:VEVENT\r\nUID:$uid\r\nDTSTART:$start\r\nSUMMARY:$title\r\n$extra\r\nEND:VEVENT';
void main() {
  test('本地搜索匹配导入日历的标题、地点、说明、备注和来源名称', () async {
    final dir = await Directory.systemTemp.createTemp(
      'calendar-subscriptions-search-test',
    );
    addTearDown(() => dir.delete(recursive: true));
    final service = SubscriptionService(
      file: File('${dir.path}/subscriptions.json'),
      fetcher: (_) async => feed(
        event(
          title: 'COMP6121 Lecture',
          extra:
              'DTEND:20260909T080000Z\r\n'
              'LOCATION:Room 6107\r\n'
              'DESCRIPTION:Bring calculator',
        ),
      ),
    );
    addTearDown(service.dispose);
    await service.initialize();
    await service.add(
      'HKU Moodle',
      await service.preview('https://example.com/calendar'),
    );
    final source = service.sources.single;
    await service.saveNote(source.id, source.events.single.key, '复习 chapter 3');

    for (final keyword in [
      'comp6121',
      '6107',
      'CALCULATOR',
      'chapter 3',
      'moodle',
    ]) {
      expect(service.searchEvents(keyword), hasLength(1));
    }
    await service.setVisible(source.id, false);
    expect(service.searchEvents('comp6121'), hasLength(1));
    expect(service.searchEvents('   '), isEmpty);
    expect(service.searchEvents('not found'), isEmpty);
  });

  test(
    'UTC, Hong Kong TZID, unfolded escaped text and all-day exclusive end',
    () {
      final e = parseSubscriptionIcs(
        feed(
          event(
            extra:
                'DTEND:20260909T095000Z\r\nLOCATION:Room\\, 1\r\nDESCRIPTION:First\\nSecond\r\n line',
          ),
        ),
      ).single;
      expect(e.start, DateTime.utc(2026, 9, 9, 15));
      expect(e.timeLabel, '15:00–17:50');
      expect(e.description, 'First\nSecondline');
      expect(e.location, 'Room, 1');
      final tz = feed(event()).replaceAll(
        'DTSTART:20260909T070000Z',
        'DTSTART;TZID=Asia/Hong_Kong:20260909T150000',
      );
      expect(parseSubscriptionIcs(tz).single.start, e.start);
      final allDay = parseSubscriptionIcs(
        feed(event(start: '20260909', extra: 'DTEND;VALUE=DATE:20260911')),
      ).single;
      expect(allDay.occursOn(DateTime(2026, 9, 10)), isTrue);
      expect(allDay.occursOn(DateTime(2026, 9, 11)), isFalse);
    },
  );
  test('zero-duration events appear on their day, including non-midnight', () {
    final e = parseSubscriptionIcs(feed(event())).single;
    expect(e.occursOn(DateTime(2026, 9, 9)), isTrue);
    expect(e.occursOn(DateTime(2026, 9, 10)), isFalse);
  });
  test(
    'truncated, malformed, duplicate identities and unsupported recurrence fail',
    () {
      for (final text in [
        '<html>login</html>',
        feed(event()).replaceAll('END:VCALENDAR', ''),
        feed(event(start: '20260230T070000Z')),
        feed('${event()}\r\n${event()}'),
        feed(event(extra: 'RRULE:FREQ=WEEKLY')),
        feed(event())
            .replaceAll('DTSTART:', 'DTSTART;TZID=Europe/London:')
            .replaceAll('070000Z', '070000'),
      ]) {
        expect(() => parseSubscriptionIcs(text), throwsFormatException);
      }
      expect(parseSubscriptionIcs(feed('')), isEmpty);
    },
  );
  test(
    'refresh updates, preserves notes and missing records, cancels explicitly, persists offline',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'calendar-subscriptions-test',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/subscriptions.json');
      var body = feed(event());
      var now = DateTime.utc(2026, 9, 8);
      var calls = 0;
      final service = SubscriptionService(
        file: file,
        fetcher: (_) async {
          calls++;
          return body;
        },
        now: () => now,
      );
      addTearDown(service.dispose);
      await service.initialize();
      await service.add(
        'HKU',
        await service.preview('https://example.com/calendar'),
      );
      final id = service.sources.single.id;
      final key = service.sources.single.events.single.key;
      await service.saveNote(id, key, 'Bring laptop');
      await service.refresh();
      expect(calls, 1);
      now = now.add(const Duration(hours: 2));
      body = feed(event(title: 'Moved', start: '20260910T070000Z'));
      await service.refresh();
      expect(service.sources.single.events.single.title, 'Moved');
      expect(service.sources.single.notes[key], 'Bring laptop');
      expect(service.eventsOn(DateTime(2026, 9, 9)), isEmpty);
      expect(service.eventsOn(DateTime(2026, 9, 10)), hasLength(1));
      body = feed('');
      await service.refresh(force: true);
      expect(service.sources.single.events.single.missing, isTrue);
      body = 'broken';
      await service.refresh(force: true);
      expect(service.sources.single.events, hasLength(1));
      expect(service.sources.single.message, contains('保留缓存'));
      final offline = SubscriptionService(
        file: file,
        fetcher: (_) async => throw const SocketException('offline'),
      );
      addTearDown(offline.dispose);
      await offline.initialize();
      expect(offline.sources.single.notes[key], 'Bring laptop');
      await offline.refresh(force: true);
      expect(offline.eventsOn(DateTime(2026, 9, 10)), hasLength(1));
      await offline.setVisible(id, false);
      expect(offline.eventsOn(DateTime(2026, 9, 10)), isEmpty);
      body = feed('BEGIN:VEVENT\r\nUID:a\r\nSTATUS:CANCELLED\r\nEND:VEVENT');
      await service.refresh(force: true);
      expect(service.sources.single.events, isEmpty);
    },
  );
  test(
    'same identities in different sources remain separate; duplicate URL rejected',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'calendar-subscriptions-test',
      );
      addTearDown(() => dir.delete(recursive: true));
      final service = SubscriptionService(
        file: File('${dir.path}/s.json'),
        fetcher: (_) async => feed(event()),
      );
      addTearDown(service.dispose);
      await service.initialize();
      final preview = await service.preview('https://example.com/a');
      await service.add('A', preview);
      await expectLater(
        service.add('Duplicate', preview),
        throwsFormatException,
      );
      await service.add('B', await service.preview('https://example.com/b'));
      expect(service.eventsOn(DateTime(2026, 9, 9)), hasLength(2));
      await service.remove(service.sources.first.id);
      expect(service.sources, hasLength(1));
    },
  );
  test(
    'HKU random UUIDs do not duplicate courses and unique same-day moves preserve notes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'hku-subscriptions-test',
      );
      addTearDown(() => dir.delete(recursive: true));
      var body = feed(event(uid: 'random-1'));
      final file = File('${dir.path}/s.json');
      final service = SubscriptionService(
        file: file,
        fetcher: (_) async => body,
      );
      addTearDown(service.dispose);
      await service.initialize();
      await service.add(
        'HKU',
        await service.preview(
          'https://hkuesd.hku.hk/eventcalendar/servlet/GetICS?token=test',
        ),
      );
      final id = service.sources.single.id;
      await service.saveNote(
        id,
        service.sources.single.events.single.key,
        'Keep note',
      );
      body = feed(event(uid: 'random-2'));
      await service.refresh(force: true);
      expect(service.sources.single.events, hasLength(1));
      expect(service.sources.single.events.single.missing, isFalse);
      body = feed(event(uid: 'random-3', start: '20260909T080000Z'));
      await service.refresh(force: true);
      expect(service.sources.single.events, hasLength(1));
      expect(service.eventsOn(DateTime(2026, 9, 9)).single.note, 'Keep note');
      expect(service.sources.single.events.single.start.hour, 16);
      // Loading an older cache also repairs duplicates while preserving notes.
      final data = service.sources.single.toJson();
      final e = service.sources.single.events.single.toJson();
      data['events'] = [
        {...e, 'key': 'old-uuid-1', 'missing': true},
        {...e, 'key': 'old-uuid-2'},
      ];
      data['notes'] = {'old-uuid-1': 'Keep note'};
      await file.writeAsString(
        jsonEncode({
          'version': 1,
          'sources': [data],
        }),
      );
      final reopened = SubscriptionService(file: file);
      addTearDown(reopened.dispose);
      await reopened.initialize();
      expect(reopened.sources.single.events, hasLength(1));
      expect(reopened.eventsOn(DateTime(2026, 9, 9)).single.note, 'Keep note');
    },
  );

  test('corrupt local storage is never overwritten', () async {
    final dir = await Directory.systemTemp.createTemp(
      'calendar-subscriptions-test',
    );
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/s.json');
    await file.writeAsString('broken');
    final service = SubscriptionService(
      file: file,
      fetcher: (_) async => feed(''),
    );
    addTearDown(service.dispose);
    await service.initialize();
    expect(service.storageError, isNotNull);
    await service.refresh(force: true);
    expect(await file.readAsString(), 'broken');
  });
}
