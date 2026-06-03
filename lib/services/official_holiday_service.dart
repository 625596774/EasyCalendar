import 'dart:convert';

import 'package:flutter/services.dart';

import '../shared/utils/date_utils.dart';

enum OfficialHolidayStatus {
  holiday('holiday', '休'),
  adjustedWorkday('adjustedWorkday', '班');

  const OfficialHolidayStatus(this.value, this.label);

  final String value;
  final String label;

  static OfficialHolidayStatus fromValue(String value) {
    return OfficialHolidayStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => OfficialHolidayStatus.holiday,
    );
  }
}

class OfficialHolidayItem {
  const OfficialHolidayItem({
    required this.date,
    required this.name,
    required this.status,
    required this.year,
    required this.source,
  });

  final DateTime date;
  final String name;
  final OfficialHolidayStatus status;
  final int year;
  final String source;
}

class OfficialHolidayService {
  final Map<int, Map<String, OfficialHolidayItem>> _cache = {};

  Future<void> loadYear(int year) async {
    if (_cache.containsKey(year)) {
      return;
    }
    final path = 'assets/data/holidays/china_official_$year.json';
    try {
      final raw = await rootBundle.loadString(path);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final items = decoded['items'] as List<dynamic>? ?? const [];
      _cache[year] = {
        for (final item in items.map((item) => item as Map<String, dynamic>))
          item['date'] as String: OfficialHolidayItem(
            date: parseDateKey(item['date'] as String),
            name: item['name'] as String,
            status: OfficialHolidayStatus.fromValue(item['status'] as String),
            year: item['year'] as int,
            source: item['source'] as String,
          ),
      };
    } catch (_) {
      _cache[year] = {};
    }
  }

  Future<void> loadYears(Iterable<int> years) async {
    for (final year in years.toSet()) {
      await loadYear(year);
    }
  }

  OfficialHolidayItem? getForDate(DateTime date) {
    return _cache[date.year]?[dateKey(date)];
  }
}
