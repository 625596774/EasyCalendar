String dateKey(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

DateTime parseDateKey(String value) {
  final parts = value.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

bool isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

int daysInMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

String weekdayName(DateTime date) {
  const names = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  return names[date.weekday - 1];
}

String monthTitle(DateTime month) => '${month.year}年${month.month}月';
