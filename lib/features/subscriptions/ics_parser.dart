/// Minimal, strict iCalendar reader for exported individual occurrences.
/// Unsupported recurrence/time zones fail the whole refresh, preserving cache.
class SubscriptionEvent {
  SubscriptionEvent({
    required this.key,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location = '',
    this.description = '',
    this.cancelled = false,
    this.missing = false,
  });
  final String key, title, location, description;
  final DateTime start, end; // Hong Kong wall-clock time, represented in UTC.
  final bool allDay, cancelled;
  bool missing;
  String get timeLabel => allDay ? '全天' : '${_hm(start)}–${_hm(end)}';
  String get preview => '${allDay ? '全天' : _hm(start)} $title';
  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  bool occursOn(DateTime day) {
    final from = DateTime.utc(day.year, day.month, day.day);
    final until = from.add(const Duration(days: 1));
    return start.isBefore(until) && (end.isAfter(from) || start == from);
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'title': title,
    'start': start.toIso8601String(),
    'end': end.toIso8601String(),
    'allDay': allDay,
    'location': location,
    'description': description,
    'cancelled': cancelled,
    'missing': missing,
  };
  factory SubscriptionEvent.fromJson(Map<String, dynamic> j) =>
      SubscriptionEvent(
        key: j['key'] as String,
        title: j['title'] as String,
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
        allDay: j['allDay'] == true,
        location: j['location'] as String? ?? '',
        description: j['description'] as String? ?? '',
        cancelled: j['cancelled'] == true,
        missing: j['missing'] == true,
      );
}

class _Property {
  _Property(this.head, this.value);
  final String head, value;
}

List<SubscriptionEvent> parseSubscriptionIcs(String text) {
  final lines = text
      .replaceFirst('\uFEFF', '')
      .replaceAll('\r\n', '\n')
      .replaceAll(RegExp(r'\n[ \t]'), '')
      .split('\n')
      .map((s) => s.trimRight());
  final result = <SubscriptionEvent>[];
  final stack = <String>[];
  Map<String, _Property>? fields;
  var calendars = 0;
  var ended = false;
  for (final line in lines) {
    if (line.isEmpty) continue;
    final colon = line.indexOf(':');
    if (colon < 0) throw const FormatException('日历格式不完整');
    final head = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final name = head.split(';').first.toUpperCase();
    if (name == 'BEGIN') {
      if (value == 'VCALENDAR') {
        if (stack.isNotEmpty || ++calendars != 1) {
          throw const FormatException('日历结构无效');
        }
      } else if (stack.isEmpty) {
        throw const FormatException('不是有效的 ICS 日历');
      }
      if (value == 'VEVENT') {
        if (stack.last != 'VCALENDAR') throw const FormatException('日程结构无效');
        fields = {};
      }
      stack.add(value);
    } else if (name == 'END') {
      if (stack.isEmpty || stack.removeLast() != value) {
        throw const FormatException('日历内容被截断');
      }
      if (value == 'VEVENT') {
        result.add(_readEvent(fields!));
        fields = null;
      }
      if (value == 'VCALENDAR') ended = true;
    } else if (stack.isEmpty) {
      throw const FormatException('不是有效的 ICS 日历');
    } else if (stack.last == 'VEVENT') {
      if (fields!.containsKey(name)) throw const FormatException('日程包含重复字段');
      fields[name] = _Property(head, value);
    }
  }
  if (!ended || stack.isNotEmpty || calendars != 1) {
    throw const FormatException('日历内容不完整');
  }
  if (result.map((e) => e.key).toSet().length != result.length) {
    throw const FormatException('日程标识重复，已保留原有课程');
  }
  return result;
}

SubscriptionEvent _readEvent(Map<String, _Property> f) {
  if (['RRULE', 'RDATE', 'EXDATE', 'EXRULE'].any(f.containsKey)) {
    throw const FormatException('此来源使用重复规则，当前版本仅支持已展开的课次');
  }
  final uid = f['UID']?.value;
  if (uid == null || uid.isEmpty) throw const FormatException('日程缺少事件标识');
  final recurrence = f['RECURRENCE-ID'];
  final key =
      '$uid\u001f${recurrence == null ? '' : _date(recurrence).toIso8601String()}';
  final cancelled = f['STATUS']?.value.toUpperCase() == 'CANCELLED';
  final startField = f['DTSTART'];
  if (startField == null && !cancelled) throw const FormatException('日程缺少开始时间');
  final start = startField == null ? DateTime.utc(1970) : _date(startField);
  final allDay = startField?.value.length == 8;
  final end = f['DTEND'] != null
      ? _date(f['DTEND']!)
      : start.add(
          allDay
              ? const Duration(days: 1)
              : f['DURATION'] != null
              ? _duration(f['DURATION']!.value)
              : Duration.zero,
        );
  if (end.isBefore(start)) throw const FormatException('日程结束时间早于开始时间');
  return SubscriptionEvent(
    key: key,
    title: _unescape(f['SUMMARY']?.value ?? '未命名日程'),
    start: start,
    end: end,
    allDay: allDay,
    cancelled: cancelled,
    location: _unescape(f['LOCATION']?.value ?? ''),
    description: _unescape(f['DESCRIPTION']?.value ?? ''),
  );
}

String _unescape(String s) => s.replaceAllMapped(
  RegExp(r'\\([nN,;\\])'),
  (m) => m[1]!.toLowerCase() == 'n' ? '\n' : m[1]!,
);

DateTime _date(_Property p) {
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$',
  ).firstMatch(p.value);
  if (match == null) throw const FormatException('无法识别日程时间');
  int n(int i) => int.parse(match[i] ?? '0');
  final d = DateTime.utc(n(1), n(2), n(3), n(4), n(5), n(6));
  if (d.year != n(1) ||
      d.month != n(2) ||
      d.day != n(3) ||
      d.hour != n(4) ||
      d.minute != n(5) ||
      d.second != n(6)) {
    throw const FormatException('无效的日程日期');
  }
  if (p.value.length == 8) return d;
  final tz = RegExp(r'(?:^|;)TZID="?([^;"]+)').firstMatch(p.head)?.group(1);
  if (match[7] != null || tz == 'UTC' || tz == 'Etc/UTC') {
    return d.add(const Duration(hours: 8));
  }
  if (tz != null && tz != 'Asia/Hong_Kong' && tz != 'Asia/Shanghai') {
    throw const FormatException('当前版本不支持该日历的时区');
  }
  return d; // Floating times are interpreted in Hong Kong.
}

Duration _duration(String s) {
  final m = RegExp(
    r'^P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
  ).firstMatch(s);
  if (m == null || s == 'P' || s == 'PT') {
    throw const FormatException('无法识别日程时长');
  }
  int n(int i) => int.parse(m[i] ?? '0');
  return Duration(
    days: n(1) * 7 + n(2),
    hours: n(3),
    minutes: n(4),
    seconds: n(5),
  );
}
