import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../database/app_database.dart';
import '../../../features/recurring_event/recurring_event_models.dart';
import '../../../features/todo/todo_repository.dart';
import '../../../services/sync/sync_service.dart';
import '../../../services/sync/sync_state.dart';
import '../../../shared/utils/date_utils.dart' as app_date;
import '../application/calendar_controller.dart';
import '../domain/calendar_day.dart';
import '../domain/daily_summary.dart';

const _jokeBearAssetCount = 193;
const _jokeBearAssetDirectory = 'assets/jokebear';
const _mobileBreakpoint = 700.0;
const _monthSwipeDistanceThreshold = 56.0;
const _monthSwipeVelocityThreshold = 320.0;
const _monthSwitchAnimationDuration = Duration(milliseconds: 240);

enum _CalendarViewMode { month, compact }

enum _MobileMonthAction { previous, today, next }

enum _MobileMoreAction { recurringEvents, importExport }

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  var _viewMode = _CalendarViewMode.month;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final message = controller.message;
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        controller.clearMessage();
      });
    }

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < _mobileBreakpoint;
          final content = Column(
            children: [
              if (isMobile)
                _MobileCalendarToolbar(controller: controller)
              else
                _CalendarToolbar(
                  controller: controller,
                  viewMode: _viewMode,
                  onViewModeChanged: (mode) => setState(() => _viewMode = mode),
                ),
              const Divider(height: 1),
              Expanded(
                child: isMobile
                    ? _MobileMonthSwipeArea(
                        controller: controller,
                        child: _MonthCalendarView(controller: controller),
                      )
                    : _viewMode == _CalendarViewMode.month
                    ? _MonthCalendarView(controller: controller)
                    : _CompactCalendarView(
                        controller: controller,
                        onShowMonthView: () =>
                            setState(() => _viewMode = _CalendarViewMode.month),
                      ),
              ),
            ],
          );

          if (!isMobile) {
            return content;
          }

          return SafeArea(child: content);
        },
      ),
    );
  }
}

class _MobileMonthSwipeArea extends StatefulWidget {
  const _MobileMonthSwipeArea({required this.controller, required this.child});

  final CalendarController controller;
  final Widget child;

  @override
  State<_MobileMonthSwipeArea> createState() => _MobileMonthSwipeAreaState();
}

class _MobileMonthSwipeAreaState extends State<_MobileMonthSwipeArea> {
  double _dragDistance = 0;
  int _pendingTransitionDirection = 0;
  int _transitionDirection = 1;
  DateTime? _lastVisibleMonth;

  @override
  Widget build(BuildContext context) {
    final visibleMonth = widget.controller.visibleMonth;
    _updateTransitionDirection(visibleMonth);
    final monthKey = ValueKey(
      '${visibleMonth.year}-${visibleMonth.month.toString().padLeft(2, '0')}',
    );

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _dragDistance = 0,
      onHorizontalDragUpdate: (details) {
        _dragDistance += details.primaryDelta ?? 0;
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final hasEnoughDistance =
            _dragDistance.abs() >= _monthSwipeDistanceThreshold;
        final hasEnoughVelocity =
            velocity.abs() >= _monthSwipeVelocityThreshold;
        if (!hasEnoughDistance && !hasEnoughVelocity) {
          return;
        }

        if (velocity < -_monthSwipeVelocityThreshold ||
            _dragDistance < -_monthSwipeDistanceThreshold) {
          _pendingTransitionDirection = 1;
          widget.controller.nextMonth();
        } else if (velocity > _monthSwipeVelocityThreshold ||
            _dragDistance > _monthSwipeDistanceThreshold) {
          _pendingTransitionDirection = -1;
          widget.controller.previousMonth();
        }
      },
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: _monthSwitchAnimationDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              children: [...previousChildren, ?currentChild],
            );
          },
          transitionBuilder: (child, animation) {
            final isIncoming = child.key == monthKey;
            final direction = _transitionDirection.toDouble();
            final begin = Offset(isIncoming ? direction : -direction, 0);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: begin,
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(key: monthKey, child: widget.child),
        ),
      ),
    );
  }

  void _updateTransitionDirection(DateTime visibleMonth) {
    final previousMonth = _lastVisibleMonth;
    if (previousMonth == null) {
      _lastVisibleMonth = visibleMonth;
      return;
    }
    if (previousMonth.year == visibleMonth.year &&
        previousMonth.month == visibleMonth.month) {
      return;
    }

    if (_pendingTransitionDirection != 0) {
      _transitionDirection = _pendingTransitionDirection;
    } else {
      _transitionDirection =
          _monthIndex(visibleMonth) >= _monthIndex(previousMonth) ? 1 : -1;
    }
    _pendingTransitionDirection = 0;
    _lastVisibleMonth = visibleMonth;
  }
}

int _monthIndex(DateTime date) {
  return date.year * 12 + date.month;
}

class _MobileCalendarToolbar extends StatelessWidget {
  const _MobileCalendarToolbar({required this.controller});

  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    final title = app_date.monthTitle(controller.visibleMonth);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: PopupMenuButton<_MobileMonthAction>(
                tooltip: '月份操作',
                onSelected: (action) => _handleMonthAction(action),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _MobileMonthAction.previous,
                    child: _PopupMenuItemContent(
                      icon: Icons.chevron_left,
                      label: '上一个月',
                    ),
                  ),
                  PopupMenuItem(
                    value: _MobileMonthAction.today,
                    child: _PopupMenuItemContent(
                      icon: Icons.today_outlined,
                      label: '回到今天',
                    ),
                  ),
                  PopupMenuItem(
                    value: _MobileMonthAction.next,
                    child: _PopupMenuItemContent(
                      icon: Icons.chevron_right,
                      label: '下一个月',
                    ),
                  ),
                ],
                child: Semantics(
                  button: true,
                  label: '当前月份 $title',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.arrow_drop_down, size: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '今天',
              onPressed: controller.goToday,
              icon: const Icon(Icons.today_outlined),
            ),
            const _SyncStatusButton(compact: true),
            PopupMenuButton<_MobileMoreAction>(
              tooltip: '更多',
              icon: const Icon(Icons.more_horiz),
              onSelected: (action) => _handleMoreAction(context, action),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _MobileMoreAction.recurringEvents,
                  child: _PopupMenuItemContent(
                    icon: Icons.cake_outlined,
                    label: '生日/纪念日',
                  ),
                ),
                PopupMenuItem(
                  value: _MobileMoreAction.importExport,
                  child: _PopupMenuItemContent(
                    icon: Icons.import_export,
                    label: '导入/导出',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleMonthAction(_MobileMonthAction action) {
    switch (action) {
      case _MobileMonthAction.previous:
        controller.previousMonth();
      case _MobileMonthAction.today:
        controller.goToday();
      case _MobileMonthAction.next:
        controller.nextMonth();
    }
  }

  void _handleMoreAction(BuildContext context, _MobileMoreAction action) {
    switch (action) {
      case _MobileMoreAction.recurringEvents:
        _showRecurringEventManager(context, controller);
      case _MobileMoreAction.importExport:
        _showImportExportDialog(context, controller);
    }
  }
}

class _PopupMenuItemContent extends StatelessWidget {
  const _PopupMenuItemContent({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon), const SizedBox(width: 12), Text(label)],
    );
  }
}

class _CalendarToolbar extends StatelessWidget {
  const _CalendarToolbar({
    required this.controller,
    required this.viewMode,
    required this.onViewModeChanged,
  });

  final CalendarController controller;
  final _CalendarViewMode viewMode;
  final ValueChanged<_CalendarViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1040;
          if (compact) {
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ..._dateControls(context, compact: true),
                _CalendarViewSwitcher(
                  viewMode: viewMode,
                  onChanged: onViewModeChanged,
                ),
                ..._globalActions(context),
              ],
            );
          }

          return Row(
            children: [
              ..._dateControls(context, compact: false),
              const SizedBox(width: 12),
              _CalendarViewSwitcher(
                viewMode: viewMode,
                onChanged: onViewModeChanged,
              ),
              const Spacer(),
              ..._globalActions(context),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _dateControls(BuildContext context, {required bool compact}) {
    if (viewMode == _CalendarViewMode.month) {
      return [
        IconButton(
          tooltip: '上一个月',
          onPressed: controller.previousMonth,
          icon: const Icon(Icons.chevron_left),
        ),
        SizedBox(
          width: 160,
          child: Center(
            child: Text(
              app_date.monthTitle(controller.visibleMonth),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
        IconButton(
          tooltip: '下一个月',
          onPressed: controller.nextMonth,
          icon: const Icon(Icons.chevron_right),
        ),
        OutlinedButton.icon(
          onPressed: controller.goToday,
          icon: const Icon(Icons.today_outlined),
          label: const Text('今天'),
        ),
      ];
    }

    return [
      SizedBox(
        width: compact ? 180 : 240,
        child: Text(
          _selectedDateTitle(controller.selectedDate),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    ];
  }

  List<Widget> _globalActions(BuildContext context) {
    return [
      const _SyncStatusButton(compact: false),
      Tooltip(
        message: '把今天之前未完成的待办移动到今天',
        child: TextButton.icon(
          onPressed: controller.moveOverdueIncompleteTodosToToday,
          icon: const Icon(Icons.low_priority),
          label: const Text('移到今天'),
        ),
      ),
      TextButton.icon(
        onPressed: () => _showRecurringEventManager(context, controller),
        icon: const Icon(Icons.cake_outlined),
        label: const Text('生日/纪念日'),
      ),
      TextButton.icon(
        onPressed: () => _showImportExportDialog(context, controller),
        icon: const Icon(Icons.import_export),
        label: const Text('导入/导出'),
      ),
    ];
  }
}

String _selectedDateTitle(DateTime date) {
  return '${date.year}年${date.month}月${date.day}日';
}

class _CalendarViewSwitcher extends StatelessWidget {
  const _CalendarViewSwitcher({
    required this.viewMode,
    required this.onChanged,
  });

  final _CalendarViewMode viewMode;
  final ValueChanged<_CalendarViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_CalendarViewMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: _CalendarViewMode.month,
          icon: Icon(Icons.calendar_month_outlined),
          label: Text('月历'),
        ),
        ButtonSegment(
          value: _CalendarViewMode.compact,
          icon: Icon(Icons.widgets_outlined),
          label: Text('小组件'),
        ),
      ],
      selected: {viewMode},
      onSelectionChanged: (selection) => onChanged(selection.single),
    );
  }
}

class _MonthCalendarView extends StatelessWidget {
  const _MonthCalendarView({required this.controller});

  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < _mobileBreakpoint;
        final showDetail = !isMobile && constraints.maxWidth >= 920;
        return Row(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isMobile ? 8 : 16,
                  isMobile ? 8 : 12,
                  showDetail
                      ? 8
                      : isMobile
                      ? 8
                      : 16,
                  isMobile ? 10 : 16,
                ),
                child: _MonthGrid(
                  controller: controller,
                  isMobile: isMobile,
                  onDateSelected: (date) {
                    controller.selectDate(date);
                    if (isMobile) {
                      _showMobileDaySummarySheet(context, controller);
                    }
                  },
                ),
              ),
            ),
            if (showDetail)
              SizedBox(
                width: 360,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 16, 16),
                  child: _DayDetailPanel(controller: controller),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CompactCalendarView extends StatelessWidget {
  const _CompactCalendarView({
    required this.controller,
    required this.onShowMonthView,
  });

  final CalendarController controller;
  final VoidCallback onShowMonthView;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CompactDateActions(
            controller: controller,
            onShowMonthView: onShowMonthView,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _SelectedDateDetailContent(
                  controller: controller,
                  showRecurringEventAction: false,
                  showTodoHeaderAction: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactDateActions extends StatelessWidget {
  const _CompactDateActions({
    required this.controller,
    required this.onShowMonthView,
  });

  final CalendarController controller;
  final VoidCallback onShowMonthView;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          onPressed: () => controller.selectDate(
            controller.selectedDate.subtract(const Duration(days: 1)),
          ),
          icon: const Icon(Icons.chevron_left),
          label: const Text('前一天'),
        ),
        OutlinedButton.icon(
          onPressed: () => controller.selectDate(DateTime.now()),
          icon: const Icon(Icons.today_outlined),
          label: const Text('今天'),
        ),
        OutlinedButton.icon(
          onPressed: () => controller.selectDate(
            controller.selectedDate.add(const Duration(days: 1)),
          ),
          icon: const Icon(Icons.chevron_right),
          label: const Text('后一天'),
        ),
        FilledButton.icon(
          onPressed: () => _showTodoDialog(context, controller),
          icon: const Icon(Icons.add_task),
          label: const Text('添加待办'),
        ),
        TextButton.icon(
          onPressed: onShowMonthView,
          icon: const Icon(Icons.calendar_month_outlined),
          label: const Text('回到月历'),
        ),
      ],
    );
  }
}

Future<void> _showMobileDaySummarySheet(
  BuildContext context,
  CalendarController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.82,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _SelectedDateDetailContent(
                      controller: controller,
                      showRecurringEventAction: false,
                      showTodoHeaderAction: true,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.controller,
    required this.isMobile,
    required this.onDateSelected,
  });

  final CalendarController controller;
  final bool isMobile;
  final ValueChanged<DateTime> onDateSelected;

  @override
  Widget build(BuildContext context) {
    final days = controller.buildDays();
    const weekDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return Column(
      children: [
        Row(
          children: weekDays
              .map(
                (day) => Expanded(
                  child: Container(
                    height: isMobile ? 28 : 32,
                    alignment: Alignment.center,
                    child: Text(
                      day,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final mainAxisSpacing = isMobile ? 3.0 : 6.0;
              final crossAxisSpacing = isMobile ? 3.0 : 6.0;
              final rowCount = days.length ~/ 7;
              final cellWidth =
                  (constraints.maxWidth - crossAxisSpacing * 6) / 7;
              final cellHeight =
                  (constraints.maxHeight - mainAxisSpacing * (rowCount - 1)) /
                  rowCount;
              final childAspectRatio = cellWidth > 0 && cellHeight > 0
                  ? cellWidth / cellHeight
                  : 1.22;

              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: mainAxisSpacing,
                  crossAxisSpacing: crossAxisSpacing,
                  childAspectRatio: childAspectRatio,
                ),
                itemCount: days.length,
                itemBuilder: (context, index) {
                  return _CalendarDayCell(
                    key: ValueKey(app_date.dateKey(days[index].date)),
                    day: days[index],
                    isMobile: isMobile,
                    onTap: () => onDateSelected(days[index].date),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    super.key,
    required this.day,
    required this.isMobile,
    required this.onTap,
  });

  final CalendarDay day;
  final bool isMobile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = !day.isCurrentMonth;
    final borderColor = day.isSelected
        ? scheme.primary
        : day.isToday
        ? scheme.tertiary
        : const Color(0xFFE2E2DD);
    final background = day.isSelected
        ? scheme.primaryContainer.withValues(alpha: 0.45)
        : day.isToday
        ? scheme.tertiaryContainer.withValues(alpha: 0.45)
        : Colors.white;
    final textColor = muted ? const Color(0xFF9AA1A8) : const Color(0xFF1F2933);
    final allLabels = [
      ...day.festivals,
      ...day.recurringEvents.map((event) => event.title),
    ];

    return Material(
      color: background,
      animationDuration: Duration.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor, width: day.isSelected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        mouseCursor: SystemMouseCursors.click,
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 96 || constraints.maxWidth < 104;
            if (isMobile) {
              return _MobileCalendarDayCellContent(
                day: day,
                textColor: textColor,
                muted: muted,
              );
            }
            if (compact) {
              return Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${day.date.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    const Spacer(),
                    if (day.officialHoliday != null &&
                        constraints.maxWidth > 58)
                      _TinyBadge(
                        text: day.officialHoliday!.status.label,
                        isWorkday:
                            day.officialHoliday!.status.value ==
                            'adjustedWorkday',
                      ),
                  ],
                ),
              );
            }
            final availableTodoRows = _availableTodoRowsForCell(
              cellHeight: constraints.maxHeight,
              hasFestivalLine: allLabels.isNotEmpty,
            );
            final visibleTodoCount = _visibleTodoCount(
              totalTodos: day.todos.length,
              availableRows: availableTodoRows,
            );
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  if (day.isCurrentMonth && constraints.maxHeight >= 104)
                    Positioned(
                      right: 4,
                      bottom: 3,
                      child: IgnorePointer(
                        child: _JokeBearImage(
                          assetPath: _jokeBearAssetForDate(day.date),
                          size: constraints.maxHeight < 128 ? 42 : 54,
                          opacity: day.isSelected ? 0.18 : 0.12,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: ClipRect(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${day.date.day}',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: textColor,
                                ),
                              ),
                              const Spacer(),
                              if (day.officialHoliday != null)
                                _TinyBadge(
                                  text: day.officialHoliday!.status.label,
                                  isWorkday:
                                      day.officialHoliday!.status.value ==
                                      'adjustedWorkday',
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            day.lunarInfo.day == 1
                                ? '${day.lunarInfo.monthText}月'
                                : day.lunarInfo.dayText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: textColor.withValues(alpha: 0.76),
                            ),
                          ),
                          if (allLabels.isNotEmpty)
                            Text(
                              allLabels.take(2).join('、'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: muted
                                    ? const Color(0xFF9AA1A8)
                                    : scheme.primary,
                              ),
                            ),
                          const SizedBox(height: 2),
                          ...day.todos
                              .take(visibleTodoCount)
                              .map(
                                (todo) => _TodoPreviewLabel(
                                  title: todo.title,
                                  urgency: todo.urgency,
                                  isCompleted: todo.isCompleted,
                                  fontSize: 12,
                                  color: todo.isCompleted
                                      ? const Color(0xFF9AA1A8)
                                      : const Color(0xFF424A53),
                                ),
                              ),
                          if (day.todos.length > visibleTodoCount &&
                              availableTodoRows > 0)
                            Text(
                              '还有 ${day.todos.length - visibleTodoCount} 项',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MobileCalendarDayCellContent extends StatelessWidget {
  const _MobileCalendarDayCellContent({
    required this.day,
    required this.textColor,
    required this.muted,
  });

  final CalendarDay day;
  final Color textColor;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final metaLabel = _mobileDayMetaLabel(day);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showMetaLabel = constraints.maxHeight >= 48;
          final showMarkers =
              constraints.maxHeight >= 58 && _hasMobileDayMarkers(day);
          final visibleTodoCount = _visibleMobileTodoCount(
            cellHeight: constraints.maxHeight,
            showMetaLabel: showMetaLabel,
            showMarkers: showMarkers,
            totalTodos: day.todos.length,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              if (day.isCurrentMonth)
                Positioned(
                  right: -2,
                  bottom: 12,
                  child: IgnorePointer(
                    child: _JokeBearImage(
                      assetPath: _jokeBearAssetForDate(day.date),
                      size: _mobileJokeBearSize(constraints),
                      opacity: _mobileJokeBearOpacity(day),
                      cacheWidth: 120,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${day.date.day}',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.05,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                        const Spacer(),
                        if (!showMarkers &&
                            day.officialHoliday != null &&
                            constraints.maxWidth > 46)
                          _TinyBadge(
                            text: day.officialHoliday!.status.label,
                            isWorkday:
                                day.officialHoliday!.status.value ==
                                'adjustedWorkday',
                          ),
                      ],
                    ),
                    if (showMetaLabel) ...[
                      const SizedBox(height: 3),
                      Text(
                        metaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.1,
                          color: muted
                              ? const Color(0xFF9AA1A8)
                              : const Color(0xFF4B5563),
                        ),
                      ),
                    ],
                    if (visibleTodoCount > 0) const SizedBox(height: 2),
                    ...day.todos
                        .take(visibleTodoCount)
                        .map(
                          (todo) => _TodoPreviewLabel(
                            title: todo.title,
                            urgency: todo.urgency,
                            isCompleted: todo.isCompleted,
                            fontSize: 10,
                            height: 1.12,
                            color: muted
                                ? const Color(0xFF9AA1A8)
                                : todo.isCompleted
                                ? const Color(0xFF9AA1A8)
                                : const Color(0xFF374151),
                          ),
                        ),
                    const Spacer(),
                    if (showMarkers) _MobileDayMarkers(day: day),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

double _mobileJokeBearSize(BoxConstraints constraints) {
  final shortestSide = constraints.maxWidth < constraints.maxHeight
      ? constraints.maxWidth
      : constraints.maxHeight;
  if (shortestSide < 56) {
    return 34;
  }
  if (shortestSide < 74) {
    return 42;
  }
  return 50;
}

double _mobileJokeBearOpacity(CalendarDay day) {
  if (!day.isCurrentMonth) {
    return 0;
  }
  if (day.todos.isNotEmpty) {
    return day.isSelected ? 0.08 : 0.055;
  }
  return day.isSelected ? 0.1 : 0.075;
}

int _visibleMobileTodoCount({
  required double cellHeight,
  required bool showMetaLabel,
  required bool showMarkers,
  required int totalTodos,
}) {
  if (totalTodos <= 0 || cellHeight < 62) {
    return 0;
  }

  const paddingHeight = 8.0;
  const dateRowHeight = 16.0;
  const metaHeight = 14.0;
  const todoGapHeight = 2.0;
  const todoLineHeight = 12.0;
  const markerHeight = 12.0;
  var usedHeight = paddingHeight + dateRowHeight;
  if (showMetaLabel) {
    usedHeight += metaHeight;
  }
  if (showMarkers) {
    usedHeight += markerHeight;
  }

  final availableRows =
      ((cellHeight - usedHeight - todoGapHeight) / todoLineHeight).floor();
  if (availableRows <= 0) {
    return 0;
  }
  return totalTodos < availableRows ? totalTodos : availableRows;
}

String _mobileDayMetaLabel(CalendarDay day) {
  if (day.festivals.isNotEmpty) {
    return day.festivals.first;
  }
  if (day.recurringEvents.isNotEmpty) {
    return day.recurringEvents.first.title;
  }
  return day.lunarInfo.day == 1
      ? '${day.lunarInfo.monthText}月'
      : day.lunarInfo.dayText;
}

class _MobileDayMarkers extends StatelessWidget {
  const _MobileDayMarkers({required this.day});

  final CalendarDay day;

  @override
  Widget build(BuildContext context) {
    final markers = <Widget>[
      if (day.recurringEvents.isNotEmpty)
        const _MobileDayDotMarker(
          color: Color(0xFFDC2626),
          semanticLabel: '有生日或纪念日',
        ),
      if (day.todos.isNotEmpty)
        const _MobileDayDotMarker(
          color: Color(0xFF2563EB),
          semanticLabel: '有待办',
        ),
      if (day.officialHoliday != null)
        _MobileDayHolidayMarker(
          text: day.officialHoliday!.status.label,
          isWorkday: day.officialHoliday!.status.value == 'adjustedWorkday',
        ),
    ].take(3).toList(growable: false);
    if (markers.isEmpty) {
      return const SizedBox(height: 12);
    }
    return SizedBox(
      height: 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: markers,
      ),
    );
  }
}

bool _hasMobileDayMarkers(CalendarDay day) {
  return day.todos.isNotEmpty ||
      day.recurringEvents.isNotEmpty ||
      day.officialHoliday != null;
}

class _MobileDayDotMarker extends StatelessWidget {
  const _MobileDayDotMarker({required this.color, required this.semanticLabel});

  final Color color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: Container(
        width: 5,
        height: 5,
        margin: const EdgeInsets.only(right: 3),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _MobileDayHolidayMarker extends StatelessWidget {
  const _MobileDayHolidayMarker({required this.text, required this.isWorkday});

  final String text;
  final bool isWorkday;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: isWorkday ? '调休上班日' : '官方休息日',
      child: Container(
        height: 12,
        constraints: const BoxConstraints(minWidth: 14),
        margin: const EdgeInsets.only(right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isWorkday ? const Color(0xFFE5E7EB) : const Color(0xFFE7F3EA),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 9,
            height: 1,
            fontWeight: FontWeight.w700,
            color: isWorkday
                ? const Color(0xFF6B7280)
                : const Color(0xFF2B6B3F),
          ),
        ),
      ),
    );
  }
}

int _availableTodoRowsForCell({
  required double cellHeight,
  required bool hasFestivalLine,
}) {
  const verticalPadding = 16.0;
  const dateRowHeight = 22.0;
  const lunarLineHeight = 15.0;
  const festivalLineHeight = 15.0;
  const spacingHeight = 4.0;
  const todoLineHeight = 15.0;

  var usedHeight =
      verticalPadding + dateRowHeight + lunarLineHeight + spacingHeight;
  if (hasFestivalLine) {
    usedHeight += festivalLineHeight;
  }

  final rows = ((cellHeight - usedHeight) / todoLineHeight).floor();
  return rows < 0 ? 0 : rows;
}

int _visibleTodoCount({required int totalTodos, required int availableRows}) {
  if (totalTodos <= 0 || availableRows <= 0) {
    return 0;
  }
  if (totalTodos <= availableRows) {
    return totalTodos;
  }
  return availableRows == 1 ? 0 : availableRows - 1;
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.text, required this.isWorkday});

  final String text;
  final bool isWorkday;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isWorkday ? const Color(0xFFFFF1D6) : const Color(0xFFE7F3EA),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          color: isWorkday ? const Color(0xFF8A5200) : const Color(0xFF2B6B3F),
        ),
      ),
    );
  }
}

class _DayDetailPanel extends StatelessWidget {
  const _DayDetailPanel({required this.controller});

  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _SelectedDateDetailContent(
          controller: controller,
          showRecurringEventAction: true,
          showTodoHeaderAction: true,
        ),
      ),
    );
  }
}

class _SelectedDateDetailContent extends StatelessWidget {
  const _SelectedDateDetailContent({
    required this.controller,
    required this.showRecurringEventAction,
    required this.showTodoHeaderAction,
  });

  final CalendarController controller;
  final bool showRecurringEventAction;
  final bool showTodoHeaderAction;

  @override
  Widget build(BuildContext context) {
    final summary = controller.selectedSummary;
    if (summary == null) {
      return const Center(child: Text('正在读取当天摘要...'));
    }
    final holiday = summary.officialHolidayStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _selectedDateTitle(summary.date),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text('${summary.weekday}  农历${summary.lunarText}'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ...summary.festivals.map((item) => _InfoChip(item)),
            if (holiday != null) _InfoChip('${holiday.name} ${holiday.label}'),
            ...summary.recurringEvents.map((item) => _InfoChip(item.title)),
          ],
        ),
        const Divider(height: 28),
        Row(
          children: [
            Text('待办事项', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (showTodoHeaderAction)
              IconButton(
                tooltip: '添加待办',
                onPressed: () => _showTodoDialog(context, controller),
                icon: const Icon(Icons.add_task),
              ),
          ],
        ),
        Expanded(
          child: summary.todos.isEmpty
              ? _EmptyTodoState(date: summary.date)
              : _TodoListWithImage(
                  date: summary.date,
                  todos: summary.todos,
                  controller: controller,
                ),
        ),
        if (showRecurringEventAction) ...[
          const Divider(height: 20),
          FilledButton.icon(
            onPressed: () => _showRecurringEventDialog(
              context,
              controller,
              initialDate: summary.date,
            ),
            icon: const Icon(Icons.cake_outlined),
            label: const Text('添加生日/纪念日'),
          ),
        ],
      ],
    );
  }
}

class _TodoListWithImage extends StatelessWidget {
  const _TodoListWithImage({
    required this.date,
    required this.todos,
    required this.controller,
  });

  final DateTime date;
  final List<DailyTodoSummary> todos;
  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          right: 18,
          bottom: 18,
          child: IgnorePointer(
            child: _JokeBearImage(
              assetPath: _jokeBearAssetForDate(date),
              size: 156,
              opacity: 0.2,
              cacheWidth: 320,
            ),
          ),
        ),
        ListView.separated(
          itemCount: todos.length,
          separatorBuilder: (_, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final todo = todos[index];
            return _TodoRow(todo: todo, controller: controller);
          },
        ),
      ],
    );
  }
}

class _EmptyTodoState extends StatelessWidget {
  const _EmptyTodoState({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _JokeBearImage(
            assetPath: _jokeBearAssetForDate(date),
            size: 148,
            opacity: 0.9,
            cacheWidth: 300,
          ),
          const SizedBox(height: 12),
          const Text('今天还没有待办'),
        ],
      ),
    );
  }
}

class _JokeBearImage extends StatelessWidget {
  const _JokeBearImage({
    required this.assetPath,
    required this.size,
    required this.opacity,
    this.cacheWidth = 160,
  });

  final String assetPath;
  final double size;
  final double opacity;
  final int cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.contain,
          cacheWidth: cacheWidth,
        ),
      ),
    );
  }
}

String _jokeBearAssetForDate(DateTime date) {
  final seed =
      date.year * 73856093 ^ date.month * 19349663 ^ date.day * 83492791;
  final index = seed.abs() % _jokeBearAssetCount + 1;
  return '$_jokeBearAssetDirectory/$index.jpg';
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _TodoPreviewLabel extends StatelessWidget {
  const _TodoPreviewLabel({
    required this.title,
    required this.urgency,
    required this.isCompleted,
    required this.fontSize,
    required this.color,
    this.height,
  });

  final String title;
  final String urgency;
  final bool isCompleted;
  final double fontSize;
  final double? height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _UrgencyDot(urgency: urgency, size: fontSize * 0.64),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: fontSize,
              height: height,
              color: color,
              decoration: isCompleted
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
            ),
          ),
        ),
      ],
    );
  }
}

class _UrgencyDot extends StatelessWidget {
  const _UrgencyDot({required this.urgency, this.size = 10});

  final String urgency;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _urgencyLabel(urgency),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _urgencyColor(urgency),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: size <= 7 ? 0.8 : 1),
        ),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.todo, required this.controller});

  final DailyTodoSummary todo;
  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: SizedBox(
        width: 58,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _UrgencyDot(urgency: todo.urgency),
            Checkbox(
              value: todo.isCompleted,
              onChanged: (value) =>
                  controller.updateSummaryTodo(todo, isCompleted: value),
            ),
          ],
        ),
      ),
      title: Text(
        todo.title,
        style: TextStyle(
          color: todo.isCompleted ? const Color(0xFF9AA1A8) : null,
          decoration: todo.isCompleted
              ? TextDecoration.lineThrough
              : TextDecoration.none,
        ),
      ),
      subtitle: todo.note == null ? null : Text(todo.note!),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            tooltip: '编辑待办',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showTodoDialog(context, controller, todo: todo),
          ),
          IconButton(
            tooltip: '删除待办',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => controller.deleteSummaryTodo(todo),
          ),
        ],
      ),
    );
  }
}

Future<void> _showTodoDialog(
  BuildContext context,
  CalendarController controller, {
  DailyTodoSummary? todo,
}) async {
  final titleController = TextEditingController(text: todo?.title ?? '');
  final noteController = TextEditingController(text: todo?.note ?? '');
  var urgency = todo?.urgency ?? TodoUrgency.green;
  final isEditing = todo != null;
  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(isEditing ? '编辑待办' : '添加待办'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: TodoUrgency.red,
                        label: _UrgencySegmentLabel(
                          label: '紧急',
                          urgency: TodoUrgency.red,
                        ),
                      ),
                      ButtonSegment(
                        value: TodoUrgency.yellow,
                        label: _UrgencySegmentLabel(
                          label: '一般',
                          urgency: TodoUrgency.yellow,
                        ),
                      ),
                      ButtonSegment(
                        value: TodoUrgency.green,
                        label: _UrgencySegmentLabel(
                          label: '不急',
                          urgency: TodoUrgency.green,
                        ),
                      ),
                    ],
                    selected: {urgency},
                    onSelectionChanged: (values) {
                      setState(() => urgency = values.single);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: '备注'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('待办标题不能为空。')),
                    );
                    return;
                  }
                  if (isEditing) {
                    await controller.updateSummaryTodo(
                      todo,
                      title: titleController.text,
                      urgency: urgency,
                      note: noteController.text,
                    );
                  } else {
                    await controller.addTodo(
                      titleController.text,
                      urgency: urgency,
                      note: noteController.text,
                    );
                  }
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _UrgencySegmentLabel extends StatelessWidget {
  const _UrgencySegmentLabel({required this.label, required this.urgency});

  final String label;
  final String urgency;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _UrgencyDot(urgency: urgency),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}

Color _urgencyColor(String urgency) {
  return switch (urgency) {
    TodoUrgency.red => const Color(0xFFE5484D),
    TodoUrgency.yellow => const Color(0xFFE0A100),
    TodoUrgency.green => const Color(0xFF2F9E44),
    _ => const Color(0xFF2F9E44),
  };
}

String _urgencyLabel(String urgency) {
  return switch (urgency) {
    TodoUrgency.red => '紧急',
    TodoUrgency.yellow => '一般',
    TodoUrgency.green => '不急',
    _ => '不急',
  };
}

class _SyncStatusButton extends StatefulWidget {
  const _SyncStatusButton({required this.compact});

  final bool compact;

  @override
  State<_SyncStatusButton> createState() => _SyncStatusButtonState();
}

class _SyncStatusButtonState extends State<_SyncStatusButton> {
  SyncService? _syncService;
  Stream<SyncState>? _stateStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final syncService = AppScope.syncOf(context);
    if (!identical(syncService, _syncService)) {
      _syncService = syncService;
      _stateStream = syncService.watchState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stateStream;
    if (stream == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<SyncState>(
      stream: stream,
      builder: (context, snapshot) {
        final presentation = _syncStatusPresentation(context, snapshot.data);
        if (widget.compact) {
          return IconButton(
            tooltip: '云同步：${presentation.label}',
            onPressed: () => _showSyncDialog(context),
            icon: Icon(presentation.icon, color: presentation.color),
          );
        }
        return TextButton.icon(
          onPressed: () => _showSyncDialog(context),
          icon: Icon(presentation.icon, color: presentation.color),
          label: Text(
            presentation.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

_SyncStatusPresentation _syncStatusPresentation(
  BuildContext context,
  SyncState? state,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (state?.status) {
    SyncStateStatus.disabled => _SyncStatusPresentation(
      icon: Icons.cloud_off_outlined,
      label: '本地模式',
      color: scheme.onSurfaceVariant,
    ),
    SyncStateStatus.unauthenticated => _SyncStatusPresentation(
      icon: Icons.cloud_off_outlined,
      label: '未登录',
      color: scheme.onSurfaceVariant,
    ),
    SyncStateStatus.pending => _SyncStatusPresentation(
      icon: Icons.cloud_queue_outlined,
      label: '待同步',
      color: const Color(0xFF9A5B00),
    ),
    SyncStateStatus.syncing => _SyncStatusPresentation(
      icon: Icons.sync,
      label: '同步中',
      color: scheme.primary,
    ),
    SyncStateStatus.failed => _SyncStatusPresentation(
      icon: Icons.sync_problem,
      label: '同步失败',
      color: scheme.error,
    ),
    SyncStateStatus.success => _SyncStatusPresentation(
      icon: Icons.cloud_done_outlined,
      label: '已同步',
      color: const Color(0xFF2F7D32),
    ),
    SyncStateStatus.idle => _SyncStatusPresentation(
      icon: Icons.cloud_done_outlined,
      label: '已登录',
      color: scheme.primary,
    ),
    null => _SyncStatusPresentation(
      icon: Icons.cloud_sync_outlined,
      label: '同步',
      color: scheme.onSurfaceVariant,
    ),
  };
}

class _SyncStatusPresentation {
  const _SyncStatusPresentation({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;
}

Future<void> _showSyncDialog(BuildContext context) async {
  final syncService = AppScope.syncOf(context);
  await showDialog<void>(
    context: context,
    builder: (context) => _SyncDialog(syncService: syncService),
  );
}

class _SyncDialog extends StatefulWidget {
  const _SyncDialog({required this.syncService});

  final SyncService syncService;

  @override
  State<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<_SyncDialog> {
  late final Stream<SyncState> _stateStream;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _stateStream = widget.syncService.watchState();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncState>(
      stream: _stateStream,
      builder: (context, snapshot) {
        final state = snapshot.data;
        return AlertDialog(
          title: const Text('云同步'),
          content: SizedBox(
            width: 420,
            child: state == null
                ? const Text('正在读取同步状态...')
                : _buildContent(context, state),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, SyncState state) {
    if (state.status == SyncStateStatus.disabled) {
      return Text(state.message ?? '当前未配置云同步，本地模式可正常使用。');
    }
    final isLoggedIn =
        state.currentUserEmail != null &&
        state.status != SyncStateStatus.unauthenticated;
    if (!isLoggedIn) {
      return _buildLoginContent(state);
    }
    return _buildLoggedInContent(state);
  }

  Widget _buildLoginContent(SyncState state) {
    final isBusy = state.status == SyncStateStatus.syncing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(state.message ?? '云同步未登录'),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          enabled: !isBusy,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: '邮箱'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          enabled: !isBusy,
          obscureText: true,
          decoration: const InputDecoration(labelText: '密码'),
          onSubmitted: (_) => _signIn(),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: isBusy ? null : _signIn,
            child: Text(isBusy ? '登录中...' : '登录'),
          ),
        ),
      ],
    );
  }

  Widget _buildLoggedInContent(SyncState state) {
    final isBusy = state.status == SyncStateStatus.syncing;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('已登录：${state.currentUserEmail}'),
        const SizedBox(height: 10),
        Text('同步状态：${_syncStatusText(state)}'),
        if (state.lastSyncedAt != null) ...[
          const SizedBox(height: 6),
          Text('上次同步：${_formatSyncTime(state.lastSyncedAt!)}'),
        ],
        if (state.message != null) ...[
          const SizedBox(height: 6),
          Text(state.message!),
        ],
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: isBusy ? null : widget.syncService.signOut,
              child: const Text('退出登录'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: isBusy ? null : widget.syncService.syncNow,
              icon: const Icon(Icons.sync),
              label: Text(isBusy ? '同步中...' : '立即同步'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      return;
    }
    await widget.syncService.signIn(email: email, password: password);
    _passwordController.clear();
  }

  String _syncStatusText(SyncState state) {
    return switch (state.status) {
      SyncStateStatus.disabled => '未配置',
      SyncStateStatus.unauthenticated => '未登录',
      SyncStateStatus.idle => '空闲',
      SyncStateStatus.pending => '待同步',
      SyncStateStatus.syncing => '同步中',
      SyncStateStatus.success => '已同步',
      SyncStateStatus.failed => '同步失败',
    };
  }

  String _formatSyncTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

Future<void> _showRecurringEventDialog(
  BuildContext context,
  CalendarController controller, {
  DateTime? initialDate,
  RecurringEvent? event,
}) async {
  final titleController = TextEditingController(text: event?.title ?? '');
  final noteController = TextEditingController(text: event?.note ?? '');
  var eventType = event == null
      ? EventType.birthday
      : EventType.fromValue(event.eventType);
  var calendarType = event == null
      ? CalendarType.solar
      : CalendarType.fromValue(event.calendarType);
  var month = event?.month ?? initialDate?.month ?? DateTime.now().month;
  var day = event?.day ?? initialDate?.day ?? DateTime.now().day;
  var isLeapMonth = event?.isLeapMonth ?? false;
  var policy = event == null
      ? LeapMonthPolicy.useNormalMonth
      : LeapMonthPolicy.fromValue(event.leapMonthPolicy);
  var enabled = event?.enabled ?? true;

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(event == null ? '添加生日/纪念日' : '编辑生日/纪念日'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '标题'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<EventType>(
                          initialValue: eventType,
                          decoration: const InputDecoration(labelText: '类型'),
                          items: EventType.values
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => eventType = value!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<CalendarType>(
                          initialValue: calendarType,
                          decoration: const InputDecoration(labelText: '日历'),
                          items: CalendarType.values
                              .map(
                                (type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type.label),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              calendarType = value!;
                              if (calendarType == CalendarType.solar) {
                                isLeapMonth = false;
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: '$month',
                          decoration: const InputDecoration(labelText: '月'),
                          keyboardType: TextInputType.number,
                          onChanged: (value) =>
                              month = int.tryParse(value) ?? month,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: '$day',
                          decoration: const InputDecoration(labelText: '日'),
                          keyboardType: TextInputType.number,
                          onChanged: (value) =>
                              day = int.tryParse(value) ?? day,
                        ),
                      ),
                    ],
                  ),
                  if (calendarType == CalendarType.lunar) ...[
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('闰月'),
                      value: isLeapMonth,
                      onChanged: (value) =>
                          setState(() => isLeapMonth = value ?? false),
                    ),
                    DropdownButtonFormField<LeapMonthPolicy>(
                      initialValue: policy,
                      decoration: const InputDecoration(labelText: '闰月不存在时'),
                      items: LeapMonthPolicy.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.label),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => policy = value!),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: '备注'),
                  ),
                  if (event != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('启用'),
                      value: enabled,
                      onChanged: (value) => setState(() => enabled = value),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  if (event == null) {
                    await controller.addRecurringEvent(
                      title: titleController.text,
                      eventType: eventType,
                      calendarType: calendarType,
                      month: month,
                      day: day,
                      isLeapMonth: isLeapMonth,
                      leapMonthPolicy: policy,
                      note: noteController.text,
                    );
                  } else {
                    await controller.updateRecurringEvent(
                      id: event.id,
                      title: titleController.text,
                      eventType: eventType,
                      calendarType: calendarType,
                      month: month,
                      day: day,
                      isLeapMonth: isLeapMonth,
                      leapMonthPolicy: policy,
                      note: noteController.text,
                      enabled: enabled,
                    );
                  }
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showRecurringEventManager(
  BuildContext context,
  CalendarController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return AlertDialog(
            title: const Text('生日/纪念日管理'),
            content: SizedBox(
              width: 620,
              height: 440,
              child: controller.recurringEvents.isEmpty
                  ? const Center(child: Text('还没有生日或纪念日规则'))
                  : ListView.separated(
                      itemCount: controller.recurringEvents.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final event = controller.recurringEvents[index];
                        final eventType = EventType.fromValue(event.eventType);
                        final calendarType = CalendarType.fromValue(
                          event.calendarType,
                        );
                        final dateText =
                            '${calendarType.label}${event.isLeapMonth ? '闰' : ''}${event.month}月${event.day}日';
                        return ListTile(
                          title: Text(event.title),
                          subtitle: Text('${eventType.label} · $dateText'),
                          leading: Icon(
                            event.enabled
                                ? Icons.notifications_none
                                : Icons.notifications_off_outlined,
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: '编辑',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _showRecurringEventDialog(
                                  context,
                                  controller,
                                  event: event,
                                ),
                              ),
                              IconButton(
                                tooltip: '删除',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    controller.deleteRecurringEvent(event.id),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
              FilledButton.icon(
                onPressed: () => _showRecurringEventDialog(context, controller),
                icon: const Icon(Icons.add),
                label: const Text('新增'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showImportExportDialog(
  BuildContext context,
  CalendarController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('导入/导出'),
        content: const Text('第一版仅导入和导出生日、纪念日规则 JSON。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await controller.importRecurringEvents();
            },
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('导入 JSON'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await controller.exportRecurringEvents();
            },
            icon: const Icon(Icons.save_alt),
            label: const Text('导出 JSON'),
          ),
        ],
      );
    },
  );
}
