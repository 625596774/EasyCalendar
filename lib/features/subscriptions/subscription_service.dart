import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'ics_parser.dart';
export 'ics_parser.dart';

typedef CalendarFetcher = Future<String> Function(Uri uri);

class CalendarSubscription {
  CalendarSubscription({
    required this.id,
    required this.name,
    required this.url,
    required this.color,
    this.visible = true,
    this.lastSuccess,
    this.lastAttempt,
    this.message,
    List<SubscriptionEvent>? events,
    Map<String, String>? notes,
  }) : events = events ?? [],
       notes = notes ?? {};
  final String id, name, url;
  final int color;
  bool visible;
  DateTime? lastSuccess, lastAttempt;
  String? message;
  List<SubscriptionEvent> events;
  final Map<String, String> notes;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'color': color,
    'visible': visible,
    'lastSuccess': lastSuccess?.toIso8601String(),
    'lastAttempt': lastAttempt?.toIso8601String(),
    'message': message,
    'events': events.map((e) => e.toJson()).toList(),
    'notes': notes,
  };
  factory CalendarSubscription.fromJson(Map<String, dynamic> j) =>
      CalendarSubscription(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String,
        color: j['color'] as int,
        visible: j['visible'] != false,
        lastSuccess: DateTime.tryParse(j['lastSuccess'] as String? ?? ''),
        lastAttempt: DateTime.tryParse(j['lastAttempt'] as String? ?? ''),
        message: j['message'] as String?,
        events: (j['events'] as List)
            .map(
              (e) => SubscriptionEvent.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        notes: Map<String, String>.from(j['notes'] as Map? ?? {}),
      );
}

class SubscriptionOccurrence {
  const SubscriptionOccurrence(this.source, this.event);
  final CalendarSubscription source;
  final SubscriptionEvent event;
  String get note => source.notes[event.key] ?? '';
}

class SubscriptionPreview {
  SubscriptionPreview(this.uri, this.events);
  final Uri uri;
  final List<SubscriptionEvent> events;
}

class SubscriptionService extends ChangeNotifier {
  SubscriptionService({
    this._file,
    CalendarFetcher? fetcher,
    DateTime Function()? now,
  }) : _fetcher = fetcher ?? _download,
       _now = now ?? DateTime.now;
  File? _file;
  final CalendarFetcher _fetcher;
  final DateTime Function() _now;
  final List<CalendarSubscription> _sources = [];
  bool _ready = false, _busy = false, _disposed = false;
  String? storageError;
  bool get busy => _busy;
  List<CalendarSubscription> get sources => List.unmodifiable(_sources);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> initialize() async {
    if (_ready) return;
    _file ??= File(
      p.join(
        (await getApplicationSupportDirectory()).path,
        'zrk_calendar',
        'calendar_subscriptions.json',
      ),
    );
    try {
      if (await _file!.exists()) {
        final data =
            jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        if (data['version'] != 1) throw const FormatException('订阅存储版本不兼容');
        _sources.addAll(
          (data['sources'] as List).map(
            (e) => CalendarSubscription.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          ),
        );
      }
      for (final source in _sources) {
        if (_isHkuTimetable(Uri.parse(source.url))) _normalizeHkuCache(source);
      }
      _ready = true;
    } catch (_) {
      storageError = '无法读取本机订阅数据，原文件已保留。请修复后重新打开应用。';
    }
    _notify();
  }

  List<SubscriptionOccurrence> eventsOn(DateTime day) {
    final items = [
      for (final s in _sources)
        if (s.visible)
          for (final e in s.events)
            if (!e.cancelled && e.occursOn(day)) SubscriptionOccurrence(s, e),
    ];
    items.sort((a, b) => a.event.start.compareTo(b.event.start));
    return items;
  }

  static Uri validateUrl(String value) {
    final uri = Uri.tryParse(value.trim().replaceAll(r'\&', '&'));
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('请输入完整的 HTTPS 日历订阅地址');
    }
    return uri;
  }

  Future<SubscriptionPreview> preview(String url) async {
    final uri = validateUrl(url);
    try {
      var events = parseSubscriptionIcs(
        await _fetcher(uri).timeout(const Duration(seconds: 30)),
      );
      if (_isHkuTimetable(uri)) {
        events = events.map(_hkuEvent).toList();
        if (events.map((e) => e.key).toSet().length != events.length) {
          throw const FormatException('课表包含无法区分的重复课次，已保留缓存');
        }
      }
      return SubscriptionPreview(uri, events);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取订阅，请检查网络和链接是否有效');
    }
  }

  Future<void> add(String name, SubscriptionPreview preview) =>
      _mutate(() async {
        if (name.trim().isEmpty) throw const FormatException('请输入订阅名称');
        if (_sources.any((s) => s.url == preview.uri.toString())) {
          throw const FormatException('此日历已经订阅');
        }
        const colors = [0xFF2563EB, 0xFF7C3AED, 0xFF0F766E, 0xFFB45309];
        _sources.add(
          CalendarSubscription(
            id: const Uuid().v4(),
            name: name.trim(),
            url: preview.uri.toString(),
            color: colors[_sources.length % colors.length],
            lastSuccess: _now(),
            lastAttempt: _now(),
            message: preview.events.isEmpty ? '来源目前没有日程' : null,
            events: preview.events.where((e) => !e.cancelled).toList(),
          ),
        );
      });

  Future<void> setVisible(String id, bool visible) => _mutate(() async {
    _sources.firstWhere((s) => s.id == id).visible = visible;
  });
  Future<void> remove(String id) => _mutate(() async {
    _sources.removeWhere((s) => s.id == id);
  });
  Future<void> saveNote(String id, String key, String note) =>
      _mutate(() async {
        _sources.firstWhere((s) => s.id == id).notes[key] = note.trim();
      });

  Future<void> refresh({String? id, bool force = false}) async {
    if (!_ready || _busy || _disposed) return;
    try {
      await _mutate(() async {
        for (final s in _sources.where((s) => id == null || s.id == id)) {
          final now = _now();
          if (!force &&
              s.lastSuccess != null &&
              now.difference(s.lastSuccess!) < const Duration(hours: 1)) {
            continue;
          }
          // Back off failed automatic requests while allowing manual retry.
          if (!force &&
              s.lastAttempt != null &&
              now.difference(s.lastAttempt!) < const Duration(minutes: 5)) {
            continue;
          }
          s.lastAttempt = now;
          try {
            final incoming = (await preview(s.url)).events;
            final merged = {for (final e in s.events) e.key: e};
            final keys = incoming.map((e) => e.key).toSet();
            if (_isHkuTimetable(Uri.parse(s.url))) {
              // HKU regenerates UUIDs on every export. Reconcile a time change
              // only when exactly one old/new occurrence of that course remains
              // on the same day. Cross-day or ambiguous changes stay flagged.
              final unmatchedOld = merged.values
                  .where((e) => !keys.contains(e.key))
                  .toList();
              final unmatchedNew = incoming
                  .where((e) => !merged.containsKey(e.key) && !e.cancelled)
                  .toList();
              for (final e in unmatchedNew) {
                final old = unmatchedOld
                    .where((o) => _sameCourseDay(o, e))
                    .toList();
                final fresh = unmatchedNew
                    .where((n) => _sameCourseDay(n, e))
                    .toList();
                if (old.length == 1 && fresh.length == 1) {
                  merged.remove(old.single.key);
                  final note = s.notes.remove(old.single.key);
                  if (note != null) s.notes.putIfAbsent(e.key, () => note);
                }
              }
            }
            for (final e in merged.values) {
              e.missing = !keys.contains(e.key);
            }
            for (final e in incoming) {
              if (e.cancelled) {
                merged.remove(e.key);
              } else {
                merged[e.key] = e;
              }
            }
            s.events = merged.values.toList();
            s.lastSuccess = _now();
            final missing = s.events.where((e) => e.missing).length;
            s.message = missing > 0
                ? '来源未返回 $missing 条缓存日程，暂时保留待核对'
                : incoming.isEmpty
                ? '来源目前没有日程'
                : null;
          } on FormatException catch (e) {
            s.message = '${e.message}；已保留缓存';
          }
        }
      });
    } catch (_) {
      storageError = '订阅保存失败，本次更新未保存；请检查磁盘空间后重试。';
      _notify();
    }
  }

  Future<void> _mutate(Future<void> Function() action) async {
    if (!_ready) throw const FormatException('本机订阅数据尚不可用');
    if (_busy) throw const FormatException('订阅正在更新，请稍后再试');
    final backup = jsonEncode(_sources.map((s) => s.toJson()).toList());
    _busy = true;
    _notify();
    try {
      await action();
      await _file!.parent.create(recursive: true);
      final temp = File('${_file!.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': 1,
          'sources': _sources.map((s) => s.toJson()).toList(),
        }),
        flush: true,
      );
      await temp.rename(_file!.path);
      storageError = null;
    } catch (_) {
      _sources
        ..clear()
        ..addAll(
          (jsonDecode(backup) as List).map(
            (e) => CalendarSubscription.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          ),
        );
      rethrow;
    } finally {
      _busy = false;
      _notify();
    }
  }

  static Future<String> _download(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      var current = uri;
      for (var redirects = 0; redirects < 5; redirects++) {
        final request = await client
            .getUrl(current)
            .timeout(const Duration(seconds: 15));
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'text/calendar');
        final response = await request.close().timeout(
          const Duration(seconds: 20),
        );
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw const FormatException('日历重定向无效');
          final next = current.resolve(location);
          if (next.scheme != 'https' ||
              next.host != uri.host ||
              next.port != uri.port) {
            throw const FormatException('日历重定向到了其他站点，请更新订阅地址');
          }
          current = next;
          continue;
        }
        if (response.statusCode != 200) {
          throw const FormatException('日历服务返回错误，请检查链接或稍后重试');
        }
        final bytes = <int>[];
        await for (final chunk in response.timeout(
          const Duration(seconds: 15),
        )) {
          bytes.addAll(chunk);
          if (bytes.length > 8 * 1024 * 1024) {
            throw const FormatException('日历文件超过 8 MB');
          }
        }
        return utf8.decode(bytes);
      }
      throw const FormatException('日历重定向次数过多');
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

// This adapter is deliberately restricted to HKU's timetable endpoint: its UID
// values are random per download. Other providers continue to use standard UID.
bool _isHkuTimetable(Uri uri) =>
    uri.host == 'hkuesd.hku.hk' && uri.path == '/eventcalendar/servlet/GetICS';

SubscriptionEvent _hkuEvent(SubscriptionEvent e) => SubscriptionEvent.fromJson({
  ...e.toJson(),
  'key': 'hku:${jsonEncode([e.title, e.start.toIso8601String()])}',
});

bool _sameCourseDay(SubscriptionEvent a, SubscriptionEvent b) =>
    a.title == b.title &&
    a.start.year == b.start.year &&
    a.start.month == b.start.month &&
    a.start.day == b.start.day;

void _normalizeHkuCache(CalendarSubscription source) {
  final merged = <String, SubscriptionEvent>{};
  for (final old in source.events) {
    final event = _hkuEvent(old);
    final previous = merged[event.key];
    if (previous == null || !event.missing) merged[event.key] = event;
    if (old.key != event.key) {
      final note = source.notes.remove(old.key);
      if (note != null && note.isNotEmpty) {
        final existing = source.notes[event.key];
        source.notes[event.key] = existing == null || existing == note
            ? note
            : '$existing\n$note';
      }
    }
  }
  source.events = merged.values.toList();
}
