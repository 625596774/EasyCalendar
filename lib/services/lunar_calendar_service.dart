import 'package:lunar/lunar.dart' as lunar;

class LunarDateInfo {
  const LunarDateInfo({
    required this.year,
    required this.month,
    required this.day,
    required this.isLeapMonth,
    required this.yearText,
    required this.monthText,
    required this.dayText,
    required this.fullText,
  });

  final int year;
  final int month;
  final int day;
  final bool isLeapMonth;
  final String yearText;
  final String monthText;
  final String dayText;
  final String fullText;
}

class LunarCalendarService {
  LunarDateInfo fromSolar(DateTime date) {
    final solar = lunar.Solar.fromYmd(date.year, date.month, date.day);
    final lunarDate = solar.getLunar();
    final month = lunarDate.getMonth();
    final yearText = lunarDate.getYearInChinese();
    final monthText = lunarDate.getMonthInChinese();
    final dayText = lunarDate.getDayInChinese();
    return LunarDateInfo(
      year: lunarDate.getYear(),
      month: month.abs(),
      day: lunarDate.getDay(),
      isLeapMonth: month < 0,
      yearText: yearText,
      monthText: monthText,
      dayText: dayText,
      fullText: '$yearText年$monthText月$dayText',
    );
  }

  DateTime? toSolar({
    required int lunarYear,
    required int lunarMonth,
    required int lunarDay,
    bool isLeapMonth = false,
  }) {
    try {
      final month = isLeapMonth ? -lunarMonth : lunarMonth;
      final lunarDate = lunar.Lunar.fromYmd(lunarYear, month, lunarDay);
      final solar = lunarDate.getSolar();
      return DateTime(solar.getYear(), solar.getMonth(), solar.getDay());
    } catch (_) {
      return null;
    }
  }

  bool hasLeapMonth(int lunarYear, int month) {
    return lunar.LunarYear.fromYear(lunarYear).getLeapMonth() == month;
  }

  int? leapMonthOfYear(int lunarYear) {
    final month = lunar.LunarYear.fromYear(lunarYear).getLeapMonth();
    return month == 0 ? null : month;
  }

  int? daysInLunarMonth({
    required int lunarYear,
    required int lunarMonth,
    bool isLeapMonth = false,
  }) {
    final month = isLeapMonth ? -lunarMonth : lunarMonth;
    return lunar.LunarYear.fromYear(lunarYear).getMonth(month)?.getDayCount();
  }

  List<String> lunarFestivals(DateTime date) {
    final solar = lunar.Solar.fromYmd(date.year, date.month, date.day);
    final lunarDate = solar.getLunar();
    return lunarDate.getFestivals();
  }
}
