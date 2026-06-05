import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../features/calendar/application/calendar_controller.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/recurring_event/recurring_event_repository.dart';
import '../features/todo/todo_repository.dart';
import '../services/festival_service.dart';
import '../services/json_import_export_service.dart';
import '../services/lunar_calendar_service.dart';
import '../services/official_holiday_service.dart';
import '../services/recurring_event_service.dart';
import '../services/todo_completion_sound_service.dart';
import 'app_scope.dart';
import 'theme/app_theme.dart';

class ZrkCalendarApp extends StatefulWidget {
  const ZrkCalendarApp({super.key});

  @override
  State<ZrkCalendarApp> createState() => _ZrkCalendarAppState();
}

class _ZrkCalendarAppState extends State<ZrkCalendarApp> {
  late final AppDatabase _database;
  late final CalendarController _controller;
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _database = AppDatabase();
    final todoRepository = TodoRepository(_database);
    final recurringEventRepository = RecurringEventRepository(_database);
    final lunarService = LunarCalendarService();
    final festivalService = FestivalService(lunarService);
    final officialHolidayService = OfficialHolidayService();
    final recurringEventService = RecurringEventService(lunarService);
    final importExportService = JsonImportExportService(
      recurringEventRepository,
    );
    const todoCompletionSoundService = TodoCompletionSoundService();
    _controller = CalendarController(
      todoRepository,
      recurringEventRepository,
      lunarService,
      festivalService,
      officialHolidayService,
      recurringEventService,
      importExportService,
      todoCompletionSoundService,
    );
    _initialization = _controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'EasyCalendar',
        theme: buildAppTheme(),
        home: FutureBuilder<void>(
          future: _initialization,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: Text('正在打开日历...')));
            }
            if (snapshot.hasError) {
              return Scaffold(
                body: Center(child: Text('初始化失败：${snapshot.error}')),
              );
            }
            return const CalendarPage();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _database.close();
    super.dispose();
  }
}
