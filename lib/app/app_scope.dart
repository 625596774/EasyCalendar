import 'package:flutter/widgets.dart';

import '../features/calendar/application/calendar_controller.dart';
import '../services/sync/sync_service.dart';

class AppScope extends InheritedNotifier<CalendarController> {
  const AppScope({
    super.key,
    required CalendarController controller,
    required this.syncService,
    required super.child,
  }) : super(notifier: controller);

  final SyncService syncService;

  static CalendarController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未初始化');
    return scope!.notifier!;
  }

  static SyncService syncOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope 未初始化');
    return scope!.syncService;
  }
}
