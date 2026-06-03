import 'lunar_calendar_service.dart';

class FestivalService {
  FestivalService(this._lunarCalendarService);

  final LunarCalendarService _lunarCalendarService;

  List<String> festivalsFor(DateTime date) {
    final festivals = <String>[
      ..._solarFixedFestivals(date),
      ..._weekBasedFestivals(date),
      ..._lunarFestivals(date),
    ];
    return festivals.toSet().toList();
  }

  List<String> _solarFixedFestivals(DateTime date) {
    final rules = <String, String>{
      '1-1': '元旦',
      '2-14': '情人节',
      '5-1': '劳动节',
      '10-1': '国庆节',
      '10-31': '万圣节',
      '12-25': '圣诞节',
    };
    final festival = rules['${date.month}-${date.day}'];
    return festival == null ? const [] : [festival];
  }

  List<String> _weekBasedFestivals(DateTime date) {
    if (date.month == 5 && date.weekday == DateTime.sunday) {
      final nthSunday = ((date.day - 1) ~/ 7) + 1;
      if (nthSunday == 2) {
        return ['母亲节'];
      }
    }
    if (date.month == 6 && date.weekday == DateTime.sunday) {
      final nthSunday = ((date.day - 1) ~/ 7) + 1;
      if (nthSunday == 3) {
        return ['父亲节'];
      }
    }
    if (date.month == 11 && date.weekday == DateTime.thursday) {
      final nthThursday = ((date.day - 1) ~/ 7) + 1;
      if (nthThursday == 4) {
        return ['感恩节'];
      }
    }
    return const [];
  }

  List<String> _lunarFestivals(DateTime date) {
    final info = _lunarCalendarService.fromSolar(date);
    final festivals = <String>[];
    if (!info.isLeapMonth) {
      if (info.month == 1 && info.day == 1) festivals.add('春节');
      if (info.month == 1 && info.day == 15) festivals.add('元宵节');
      if (info.month == 5 && info.day == 5) festivals.add('端午节');
      if (info.month == 7 && info.day == 7) festivals.add('七夕');
      if (info.month == 8 && info.day == 15) festivals.add('中秋节');
      if (info.month == 9 && info.day == 9) festivals.add('重阳节');
    }
    if (_lunarCalendarService.lunarFestivals(date).contains('除夕')) {
      festivals.add('除夕');
    }
    return festivals;
  }
}
