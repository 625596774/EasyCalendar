import 'package:flutter/widgets.dart';

import '../features/calendar/application/calendar_controller.dart';

class AppScope extends InheritedNotifier<CalendarController> {
  const AppScope({
    super.key,
    required CalendarController controller,
    required super.child,
  }) : super(notifier: controller);

  static CalendarController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未初始化');
    return scope!.notifier!;
  }
}
