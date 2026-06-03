import 'package:flutter/material.dart';

import '../../../app/app_scope.dart';
import '../../../database/app_database.dart';
import '../../../features/recurring_event/recurring_event_models.dart';
import '../../../shared/utils/date_utils.dart' as app_date;
import '../application/calendar_controller.dart';
import '../domain/calendar_day.dart';

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final message = controller.message;
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        controller.clearMessage();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ZRK 日历'),
        actions: [
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
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          _CalendarToolbar(controller: controller),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showDetail = constraints.maxWidth >= 920;
                return Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          showDetail ? 8 : 16,
                          16,
                        ),
                        child: _MonthGrid(controller: controller),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarToolbar extends StatelessWidget {
  const _CalendarToolbar({required this.controller});

  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
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
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: controller.goToday,
            icon: const Icon(Icons.today_outlined),
            label: const Text('今天'),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.controller});

  final CalendarController controller;

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
                    height: 32,
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
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.22,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              return _CalendarDayCell(
                key: ValueKey(app_date.dateKey(days[index].date)),
                day: days[index],
                onTap: () => controller.selectDate(days[index].date),
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
    required this.onTap,
  });

  final CalendarDay day;
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
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight < 72 || constraints.maxWidth < 92;
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
                    if (day.officialHoliday != null && constraints.maxWidth > 58)
                      _TinyBadge(
                        text: day.officialHoliday!.status.label,
                        isWorkday: day.officialHoliday!.status.value ==
                            'adjustedWorkday',
                      ),
                  ],
                ),
              );
            }
            return Padding(
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
                            isWorkday: day.officialHoliday!.status.value ==
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
                          color:
                              muted ? const Color(0xFF9AA1A8) : scheme.primary,
                        ),
                      ),
                    const SizedBox(height: 2),
                    ...day.todos.take(2).map(
                          (todo) => Text(
                            todo.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: todo.isCompleted
                                  ? const Color(0xFF9AA1A8)
                                  : const Color(0xFF424A53),
                              decoration: todo.isCompleted
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                    if (day.todos.length > 2)
                      Text(
                        '还有 ${day.todos.length - 2} 项',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
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
    final selected = controller.selectedDate;
    final lunar = controller.selectedLunarInfo;
    final holiday = controller.selectedOfficialHoliday;
    final occurrences = controller.selectedOccurrences;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${selected.year}年${selected.month}月${selected.day}日',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text('${app_date.weekdayName(selected)}  农历${lunar.fullText}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...controller.selectedFestivals.map((item) => _InfoChip(item)),
                if (holiday != null)
                  _InfoChip('${holiday.name} ${holiday.status.label}'),
                ...occurrences.map((item) => _InfoChip(item.title)),
              ],
            ),
            const Divider(height: 28),
            Row(
              children: [
                Text('待办事项', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  tooltip: '添加待办',
                  onPressed: () => _showTodoDialog(context, controller),
                  icon: const Icon(Icons.add_task),
                ),
              ],
            ),
            Expanded(
              child: controller.selectedTodos.isEmpty
                  ? const Center(child: Text('今天还没有待办'))
                  : ListView.separated(
                      itemCount: controller.selectedTodos.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final todo = controller.selectedTodos[index];
                        return _TodoRow(todo: todo, controller: controller);
                      },
                    ),
            ),
            const Divider(height: 20),
            FilledButton.icon(
              onPressed: () => _showRecurringEventDialog(
                context,
                controller,
                initialDate: controller.selectedDate,
              ),
              icon: const Icon(Icons.cake_outlined),
              label: const Text('添加生日/纪念日'),
            ),
          ],
        ),
      ),
    );
  }
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

class _TodoRow extends StatelessWidget {
  const _TodoRow({
    required this.todo,
    required this.controller,
  });

  final TodoItem todo;
  final CalendarController controller;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: todo.isCompleted,
        onChanged: (value) => controller.updateTodo(todo, isCompleted: value),
      ),
      title: Text(
        todo.title,
        style: TextStyle(
          color: todo.isCompleted ? const Color(0xFF9AA1A8) : null,
          decoration:
              todo.isCompleted ? TextDecoration.lineThrough : TextDecoration.none,
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
            onPressed: () => controller.deleteTodo(todo),
          ),
        ],
      ),
    );
  }
}

Future<void> _showTodoDialog(
  BuildContext context,
  CalendarController controller, {
  TodoItem? todo,
}) async {
  final titleController = TextEditingController(text: todo?.title ?? '');
  final noteController = TextEditingController(text: todo?.note ?? '');
  final isEditing = todo != null;
  await showDialog<void>(
    context: context,
    builder: (context) {
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
            TextField(
              controller: noteController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '备注'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              if (isEditing) {
                await controller.updateTodo(
                  todo,
                  title: titleController.text,
                  note: noteController.text,
                );
              } else {
                await controller.addTodo(
                  titleController.text,
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
                              .map((type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(type.label),
                                  ))
                              .toList(),
                          onChanged: (value) => setState(() => eventType = value!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<CalendarType>(
                          initialValue: calendarType,
                          decoration: const InputDecoration(labelText: '日历'),
                          items: CalendarType.values
                              .map((type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(type.label),
                                  ))
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
                          onChanged: (value) => month = int.tryParse(value) ?? month,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          initialValue: '$day',
                          decoration: const InputDecoration(labelText: '日'),
                          keyboardType: TextInputType.number,
                          onChanged: (value) => day = int.tryParse(value) ?? day,
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
                          .map((item) => DropdownMenuItem(
                                value: item,
                                child: Text(item.label),
                              ))
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
                        final calendarType =
                            CalendarType.fromValue(event.calendarType);
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
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
