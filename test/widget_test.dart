import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/shared/utils/date_utils.dart' as app_date;

void main() {
  test('日期工具可以生成稳定日期键', () {
    expect(app_date.dateKey(DateTime(2026, 6, 10)), '2026-06-10');
  });
}
