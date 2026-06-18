import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../../database/app_database.dart';
import '../../../features/recurring_event/recurring_event_models.dart';
import '../../../features/recurring_event/recurring_event_repository.dart';
import '../../../features/todo/todo_repository.dart';
import '../../../services/festival_service.dart';
import '../../../services/daily_summary_service.dart';
import '../../../services/json_import_export_service.dart';
import '../../../services/lunar_calendar_service.dart';
import '../../../services/official_holiday_service.dart';
import '../../../services/recurring_event_service.dart';
import '../../../services/today_summary_export_service.dart';
import '../../../services/todo_completion_sound_service.dart';
import '../../../shared/utils/date_utils.dart';
import '../domain/calendar_day.dart';
import '../domain/daily_summary.dart';

class CalendarController extends ChangeNotifier {
  CalendarController(
    this._todoRepository,
    this._recurringEventRepository,
    this._lunarCalendarService,
    this._festivalService,
    this._officialHolidayService,
    this._recurringEventService,
    this._dailySummaryService,
    this._todaySummaryExportService,
    this._jsonImportExportService,
    this._todoCompletionSoundService, {
    this.onLocalDataChanged,
  }) {
    _selectedDate = dateOnly(DateTime.now());
    _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
  }

  final TodoRepository _todoRepository;
  final RecurringEventRepository _recurringEventRepository;
  final LunarCalendarService _lunarCalendarService;
  final FestivalService _festivalService;
  final OfficialHolidayService _officialHolidayService;
  final RecurringEventService _recurringEventService;
  final DailySummaryService _dailySummaryService;
  final TodaySummaryExportService _todaySummaryExportService;
  final JsonImportExportService _jsonImportExportService;
  final TodoCompletionSoundService _todoCompletionSoundService;
  final VoidCallback? onLocalDataChanged;

  late DateTime _visibleMonth;
  late DateTime _selectedDate;
  List<TodoItem> _selectedTodos = [];
  List<RecurringEvent> _recurringEvents = [];
  List<_BaseCalendarDay>? _baseDaysCache;
  String? _baseDaysCacheKey;
  Map<String, List<TodoItem>> _visibleTodoMap = {};
  Map<String, List<EventOccurrence>> _occurrenceMap = {};
  DailySummary? _selectedSummary;
  LunarDateInfo? _selectedLunarInfoCache;
  List<String>? _selectedFestivalsCache;
  DateTime? _selectedInfoCacheDate;
  StreamSubscription<List<TodoItem>>? _visibleTodoSubscription;
  StreamSubscription<List<TodoItem>>? _selectedTodoSubscription;
  StreamSubscription<List<TodoItem>>? _todayTodoSubscription;
  StreamSubscription<List<RecurringEvent>>? _recurringEventSubscription;
  int _selectedSummaryRequestId = 0;
  bool _isReady = false;
  bool _isDisposed = false;
  String? _message;
  String? _lastTodaySummaryExportError;

  DateTime get visibleMonth => _visibleMonth;
  DateTime get selectedDate => _selectedDate;
  bool get isReady => _isReady;
  String? get message => _message;
  List<TodoItem> get selectedTodos => _selectedTodos;
  List<RecurringEvent> get recurringEvents => _recurringEvents;
  DailySummary? get selectedSummary => _selectedSummary;
  String? get lastTodaySummaryExportError => _lastTodaySummaryExportError;
  LunarDateInfo get selectedLunarInfo {
    _ensureSelectedInfoCache();
    return _selectedLunarInfoCache!;
  }

  List<String> get selectedFestivals {
    _ensureSelectedInfoCache();
    return _selectedFestivalsCache!;
  }

  OfficialHolidayItem? get selectedOfficialHoliday =>
      _officialHolidayService.getForDate(_selectedDate);
  List<EventOccurrence> get selectedOccurrences {
    final key = dateKey(_selectedDate);
    return _occurrenceMap[key] ?? const [];
  }

  Future<void> initialize() async {
    await _loadHolidayYearsForVisibleMonth();
    _watchTodos();
    _watchSelectedTodos();
    _watchTodayTodos();
    _recurringEventSubscription = _recurringEventRepository
        .watchEvents()
        .listen((events) {
          _recurringEvents = events;
          _rebuildOccurrenceMap();
          unawaited(_refreshSelectedSummary());
          unawaited(_exportTodaySummary());
          notifyListeners();
        });
    await _refreshSelectedSummary();
    unawaited(_exportTodaySummary());
    _isReady = true;
    notifyListeners();
  }

  List<CalendarDay> buildDays() {
    return _baseDays()
        .map((baseDay) {
          final key = dateKey(baseDay.date);
          return CalendarDay(
            date: baseDay.date,
            isCurrentMonth: baseDay.isCurrentMonth,
            isToday: baseDay.isToday,
            isSelected: isSameDate(baseDay.date, _selectedDate),
            lunarInfo: baseDay.lunarInfo,
            festivals: baseDay.festivals,
            todos: _visibleTodoMap[key] ?? const [],
            recurringEvents: _occurrenceMap[key] ?? const [],
            officialHoliday: baseDay.officialHoliday,
          );
        })
        .toList(growable: false);
  }

  void selectDate(DateTime date) {
    final normalized = dateOnly(date);
    if (isSameDate(normalized, _selectedDate)) {
      return;
    }
    _selectedDate = normalized;
    _invalidateSelectedInfoCache();
    _selectedSummary = null;
    final monthChanged =
        _selectedDate.month != _visibleMonth.month ||
        _selectedDate.year != _visibleMonth.year;
    notifyListeners();

    if (monthChanged) {
      _visibleMonth = DateTime(_selectedDate.year, _selectedDate.month);
      _invalidateBaseDaysCache();
      _loadHolidayYearsForVisibleMonth().then((_) {
        _invalidateBaseDaysCache();
        _watchTodos();
        _rebuildOccurrenceMap();
        notifyListeners();
      });
    }
    _watchSelectedTodos();
    unawaited(_refreshSelectedSummary());
  }

  Future<void> previousMonth() async {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    await _loadHolidayYearsForVisibleMonth();
    _invalidateBaseDaysCache();
    _watchTodos();
    _rebuildOccurrenceMap();
    notifyListeners();
  }

  Future<void> nextMonth() async {
    _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    await _loadHolidayYearsForVisibleMonth();
    _invalidateBaseDaysCache();
    _watchTodos();
    _rebuildOccurrenceMap();
    notifyListeners();
  }

  Future<void> goToday() async {
    final today = dateOnly(DateTime.now());
    _selectedDate = today;
    _visibleMonth = DateTime(today.year, today.month);
    _invalidateSelectedInfoCache();
    _selectedSummary = null;
    await _loadHolidayYearsForVisibleMonth();
    _invalidateBaseDaysCache();
    _watchTodos();
    _watchSelectedTodos();
    _rebuildOccurrenceMap();
    await _refreshSelectedSummary();
    notifyListeners();
  }

  Future<void> addTodo(
    String title, {
    String urgency = TodoUrgency.green,
    String? note,
  }) async {
    if (title.trim().isEmpty) {
      _setMessage('待办标题不能为空。');
      return;
    }
    await _todoRepository.addTodo(
      title: title,
      date: _selectedDate,
      urgency: urgency,
      note: note,
    );
    _notifyLocalDataChanged();
    if (_isToday(_selectedDate)) {
      unawaited(_exportTodaySummary());
    }
  }

  Future<void> updateTodo(
    TodoItem todo, {
    String? title,
    bool? isCompleted,
    String? urgency,
    String? note,
  }) async {
    if (title != null && title.trim().isEmpty) {
      _setMessage('待办标题不能为空。');
      return;
    }
    final shouldPlayCompletionSound = !todo.isCompleted && isCompleted == true;
    await _todoRepository.updateTodo(
      id: todo.id,
      title: title,
      isCompleted: isCompleted,
      urgency: urgency,
      note: note,
    );
    _notifyLocalDataChanged();
    if (shouldPlayCompletionSound) {
      _todoCompletionSoundService.playCompleted();
    }
    if (_isToday(todo.date)) {
      unawaited(_exportTodaySummary());
    }
  }

  Future<void> deleteTodo(TodoItem todo) async {
    await _todoRepository.deleteTodo(todo.id);
    _notifyLocalDataChanged();
    if (_isToday(todo.date)) {
      unawaited(_exportTodaySummary());
    }
  }

  Future<void> moveOverdueIncompleteTodosToToday() async {
    final today = dateOnly(DateTime.now());
    final movedCount = await _todoRepository.moveIncompleteTodosBeforeDate(
      beforeDate: today,
      targetDate: today,
    );
    if (movedCount == 0) {
      _setMessage('没有需要移动的过期待办。');
      return;
    }
    _notifyLocalDataChanged();
    unawaited(_exportTodaySummary());
    _setMessage('已移动 $movedCount 条未完成待办到今天。');
  }

  Future<void> updateSummaryTodo(
    DailyTodoSummary todo, {
    String? title,
    bool? isCompleted,
    String? urgency,
    String? note,
  }) async {
    if (title != null && title.trim().isEmpty) {
      _setMessage('待办标题不能为空。');
      return;
    }
    final shouldPlayCompletionSound = !todo.isCompleted && isCompleted == true;
    await _todoRepository.updateTodo(
      id: todo.id,
      title: title,
      isCompleted: isCompleted,
      urgency: urgency,
      note: note,
    );
    _notifyLocalDataChanged();
    if (shouldPlayCompletionSound) {
      _todoCompletionSoundService.playCompleted();
    }
    if (_isToday(_selectedDate)) {
      unawaited(_exportTodaySummary());
    }
  }

  Future<void> deleteSummaryTodo(DailyTodoSummary todo) async {
    await _todoRepository.deleteTodo(todo.id);
    _notifyLocalDataChanged();
    if (_isToday(_selectedDate)) {
      unawaited(_exportTodaySummary());
    }
  }

  Future<void> addRecurringEvent({
    required String title,
    required EventType eventType,
    required CalendarType calendarType,
    required int month,
    required int day,
    required bool isLeapMonth,
    required LeapMonthPolicy leapMonthPolicy,
    String? note,
  }) async {
    if (title.trim().isEmpty) {
      _setMessage('标题不能为空。');
      return;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      _setMessage('日期必须是有效的月日。');
      return;
    }
    await _recurringEventRepository.addEvent(
      title: title,
      eventType: eventType,
      calendarType: calendarType,
      month: month,
      day: day,
      isLeapMonth: isLeapMonth,
      leapMonthPolicy: leapMonthPolicy,
      note: note,
    );
    _notifyLocalDataChanged();
    unawaited(_exportTodaySummary());
  }

  Future<void> updateRecurringEvent({
    required String id,
    required String title,
    required EventType eventType,
    required CalendarType calendarType,
    required int month,
    required int day,
    required bool isLeapMonth,
    required LeapMonthPolicy leapMonthPolicy,
    required String? note,
    required bool enabled,
  }) async {
    await _recurringEventRepository.updateEvent(
      id: id,
      title: title,
      eventType: eventType,
      calendarType: calendarType,
      month: month,
      day: day,
      isLeapMonth: isLeapMonth,
      leapMonthPolicy: leapMonthPolicy,
      note: note,
      enabled: enabled,
    );
    _notifyLocalDataChanged();
    unawaited(_exportTodaySummary());
  }

  Future<void> deleteRecurringEvent(String id) async {
    await _recurringEventRepository.deleteEvent(id);
    _notifyLocalDataChanged();
    unawaited(_exportTodaySummary());
  }

  Future<void> importRecurringEvents() async {
    final picked = await FilePicker.pickFiles(
      dialogTitle: '选择生日/纪念日 JSON',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = picked?.files.single.path;
    if (path == null) {
      return;
    }
    final result = await _jsonImportExportService.importFromFile(path);
    if (result.importedCount > 0) {
      _notifyLocalDataChanged();
    }
    unawaited(_exportTodaySummary());
    final errorText = result.hasErrors ? '，${result.errors.join('；')}' : '';
    _setMessage('已导入 ${result.importedCount} 条规则$errorText');
  }

  Future<void> exportRecurringEvents() async {
    final path = await FilePicker.saveFile(
      dialogTitle: '导出生日/纪念日 JSON',
      fileName: 'zrk_calendar_recurring_events.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) {
      return;
    }
    await _jsonImportExportService.exportToFile(path);
    _setMessage('已导出到 ${File(path).path}');
  }

  void clearMessage() {
    _message = null;
    notifyListeners();
  }

  Future<void> _loadHolidayYearsForVisibleMonth() async {
    final range = _visibleMonthGridRange();
    await _officialHolidayService.loadYears([
      range.start.year,
      _visibleMonth.year,
      range.end.year,
    ]);
  }

  void _watchTodos() {
    _visibleTodoSubscription?.cancel();
    final range = _visibleMonthGridRange();
    _visibleTodoSubscription = _todoRepository
        .watchTodosForRange(range.start, range.end)
        .listen((todos) {
          _visibleTodoMap = _todosByDate(todos);
          notifyListeners();
        });
  }

  void _watchSelectedTodos() {
    _selectedTodoSubscription?.cancel();
    _selectedTodoSubscription = _todoRepository
        .watchTodosForDate(_selectedDate)
        .listen((todos) {
          _selectedTodos = todos;
          unawaited(_refreshSelectedSummary());
          notifyListeners();
        });
  }

  void _watchTodayTodos() {
    _todayTodoSubscription?.cancel();
    final today = dateOnly(DateTime.now());
    _todayTodoSubscription = _todoRepository.watchTodosForDate(today).listen((
      _,
    ) {
      unawaited(_exportTodaySummary());
    });
  }

  Future<void> _refreshSelectedSummary() async {
    final requestId = ++_selectedSummaryRequestId;
    final selectedDate = _selectedDate;
    final summary = await _dailySummaryService.buildForDate(selectedDate);
    if (_isDisposed ||
        requestId != _selectedSummaryRequestId ||
        !isSameDate(selectedDate, _selectedDate)) {
      return;
    }
    _selectedSummary = summary;
    notifyListeners();
  }

  Future<void> _exportTodaySummary() async {
    final result = await _todaySummaryExportService.exportToday();
    if (_isDisposed) {
      return;
    }
    _lastTodaySummaryExportError = result.isSuccess ? null : result.error;
    if (!result.isSuccess) {
      debugPrint('today_summary 导出失败：${result.error ?? 'unknown'}');
    }
  }

  bool _isToday(DateTime date) {
    return isSameDate(date, DateTime.now());
  }

  void _rebuildOccurrenceMap() {
    final years = <int>{_visibleMonth.year, _selectedDate.year};
    final range = _visibleMonthGridRange();
    years.add(range.start.year);
    years.add(range.end.year);
    _occurrenceMap = _recurringEventService.occurrencesByDate(
      _recurringEvents,
      years,
    );
  }

  List<_BaseCalendarDay> _baseDays() {
    final today = dateOnly(DateTime.now());
    final key =
        '${_visibleMonth.year}-${_visibleMonth.month}-${dateKey(today)}';
    if (_baseDaysCacheKey == key && _baseDaysCache != null) {
      return _baseDaysCache!;
    }

    final range = _visibleMonthGridRange();
    final dayCount = range.end.difference(range.start).inDays + 1;
    final days = List.generate(dayCount, (index) {
      final date = range.start.add(Duration(days: index));
      return _BaseCalendarDay(
        date: date,
        isCurrentMonth: date.month == _visibleMonth.month,
        isToday: isSameDate(date, today),
        lunarInfo: _lunarCalendarService.fromSolar(date),
        festivals: _festivalService.festivalsFor(date),
        officialHoliday: _officialHolidayService.getForDate(date),
      );
    }, growable: false);
    _baseDaysCache = days;
    _baseDaysCacheKey = key;
    return days;
  }

  _DateRange _visibleMonthGridRange() {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month);
    final last = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0);
    final start = first.subtract(
      Duration(days: first.weekday - DateTime.monday),
    );
    final end = last.add(Duration(days: DateTime.sunday - last.weekday));
    return _DateRange(start: start, end: end);
  }

  Map<String, List<TodoItem>> _todosByDate(List<TodoItem> todos) {
    final todoMap = <String, List<TodoItem>>{};
    for (final todo in todos) {
      todoMap.putIfAbsent(dateKey(todo.date), () => []).add(todo);
    }
    return todoMap;
  }

  void _ensureSelectedInfoCache() {
    if (_selectedInfoCacheDate != null &&
        isSameDate(_selectedInfoCacheDate!, _selectedDate) &&
        _selectedLunarInfoCache != null &&
        _selectedFestivalsCache != null) {
      return;
    }
    _selectedInfoCacheDate = _selectedDate;
    _selectedLunarInfoCache = _lunarCalendarService.fromSolar(_selectedDate);
    _selectedFestivalsCache = _festivalService.festivalsFor(_selectedDate);
  }

  void _invalidateSelectedInfoCache() {
    _selectedInfoCacheDate = null;
    _selectedLunarInfoCache = null;
    _selectedFestivalsCache = null;
  }

  void _invalidateBaseDaysCache() {
    _baseDaysCache = null;
    _baseDaysCacheKey = null;
  }

  void _setMessage(String message) {
    _message = message;
    notifyListeners();
  }

  void _notifyLocalDataChanged() {
    onLocalDataChanged?.call();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _visibleTodoSubscription?.cancel();
    _selectedTodoSubscription?.cancel();
    _todayTodoSubscription?.cancel();
    _recurringEventSubscription?.cancel();
    super.dispose();
  }
}

class _BaseCalendarDay {
  const _BaseCalendarDay({
    required this.date,
    required this.isCurrentMonth,
    required this.isToday,
    required this.lunarInfo,
    required this.festivals,
    required this.officialHoliday,
  });

  final DateTime date;
  final bool isCurrentMonth;
  final bool isToday;
  final LunarDateInfo lunarInfo;
  final List<String> festivals;
  final OfficialHolidayItem? officialHoliday;
}

class _DateRange {
  const _DateRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}
