import 'dart:async';

import 'package:flutter/material.dart';

import '../database/app_database.dart';
import '../features/calendar/application/calendar_controller.dart';
import '../features/calendar/presentation/calendar_page.dart';
import '../features/recurring_event/recurring_event_repository.dart';
import '../features/todo/todo_repository.dart';
import '../services/daily_summary_service.dart';
import '../services/festival_service.dart';
import '../services/json_import_export_service.dart';
import '../services/lunar_calendar_service.dart';
import '../services/official_holiday_service.dart';
import '../services/recurring_event_service.dart';
import '../services/sync/auto_sync_coordinator.dart';
import '../services/sync/noop_sync_service.dart';
import '../services/sync/supabase_bootstrap.dart';
import '../services/sync/supabase_sync_service.dart';
import '../services/sync/sync_service.dart';
import '../services/today_summary_export_service.dart';
import '../services/todo_completion_sound_service.dart';
import 'app_scope.dart';
import 'theme/app_theme.dart';

class ZrkCalendarApp extends StatefulWidget {
  const ZrkCalendarApp({super.key, required this.supabaseBootstrap});

  final SupabaseBootstrapResult supabaseBootstrap;

  @override
  State<ZrkCalendarApp> createState() => _ZrkCalendarAppState();
}

class _ZrkCalendarAppState extends State<ZrkCalendarApp> {
  late final AppDatabase _database;
  late final CalendarController _controller;
  late final SyncService _syncService;
  late final Future<void> _initialization;
  late final _LifecycleObserver _lifecycleObserver;
  AutoSyncCoordinator? _autoSyncCoordinator;
  AppLifecycleState? _lastLifecycleState;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = _LifecycleObserver(_handleLifecycle);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    _lastLifecycleState = WidgetsBinding.instance.lifecycleState;
    _database = AppDatabase();
    final todoRepository = TodoRepository(_database);
    final recurringEventRepository = RecurringEventRepository(_database);
    final lunarService = LunarCalendarService();
    final festivalService = FestivalService(lunarService);
    final officialHolidayService = OfficialHolidayService();
    final recurringEventService = RecurringEventService(lunarService);
    final dailySummaryService = DailySummaryService(
      todoRepository: todoRepository,
      recurringEventRepository: recurringEventRepository,
      lunarCalendarService: lunarService,
      festivalService: festivalService,
      officialHolidayService: officialHolidayService,
      recurringEventService: recurringEventService,
    );
    final todaySummaryExportService = TodaySummaryExportService(
      dailySummaryService: dailySummaryService,
    );
    final importExportService = JsonImportExportService(
      recurringEventRepository,
    );
    final supabaseClient = widget.supabaseBootstrap.client;
    if (supabaseClient == null) {
      _syncService = NoopSyncService(message: widget.supabaseBootstrap.message);
    } else {
      final supabaseSyncService = SupabaseSyncService(
        client: supabaseClient,
        todoRepository: todoRepository,
        recurringEventRepository: recurringEventRepository,
      );
      _autoSyncCoordinator = AutoSyncCoordinator(
        syncService: supabaseSyncService,
        pendingSyncItemsChecker: () async {
          if (await todoRepository.hasPendingTodosIncludingDeleted()) {
            return true;
          }
          return recurringEventRepository.hasPendingEventsIncludingDeleted();
        },
      );
      _syncService = _autoSyncCoordinator!;
    }
    const todoCompletionSoundService = TodoCompletionSoundService();
    _controller = CalendarController(
      todoRepository,
      recurringEventRepository,
      lunarService,
      festivalService,
      officialHolidayService,
      recurringEventService,
      dailySummaryService,
      todaySummaryExportService,
      importExportService,
      todoCompletionSoundService,
      onLocalDataChanged: () {
        unawaited(_autoSyncCoordinator?.notifyLocalChange());
      },
    );
    _initialization = _controller.initialize();
    unawaited(_syncService.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      syncService: _syncService,
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
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _controller.dispose();
    unawaited(_syncService.dispose());
    _database.close();
    super.dispose();
  }

  void _handleLifecycle(AppLifecycleState state) {
    final previous = _lastLifecycleState;
    _lastLifecycleState = state;
    if (state == AppLifecycleState.resumed &&
        previous != null &&
        previous != AppLifecycleState.resumed) {
      unawaited(_autoSyncCoordinator?.handleAppResumed());
    }
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  _LifecycleObserver(this.onChanged);

  final ValueChanged<AppLifecycleState> onChanged;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onChanged(state);
  }
}
