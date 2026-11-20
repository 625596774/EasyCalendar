import 'package:flutter/material.dart';
import 'subscription_service.dart';

Future<void> showSubscriptionManager(
  BuildContext context,
  SubscriptionService service,
) => showDialog<void>(
  context: context,
  builder: (_) => _Manager(service: service),
);

class _Manager extends StatefulWidget {
  const _Manager({required this.service});
  final SubscriptionService service;
  @override
  State<_Manager> createState() => _ManagerState();
}

class _ManagerState extends State<_Manager> {
  String? error;
  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => error = null);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message.toString()
              : '操作未保存，请稍后重试',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) {
      final service = widget.service;
      return AlertDialog(
        title: const Text('日历订阅'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('启动或回到前台时，距上次成功更新超过 1 小时会自动刷新。日程按香港时间显示，离线时可查看缓存。'),
                const SizedBox(height: 12),
                if (service.busy) const LinearProgressIndicator(),
                if (service.storageError != null)
                  Text(
                    service.storageError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (service.sources.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('尚未添加日历订阅'),
                  ),
                for (final s in service.sources)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_month, color: Color(s.color)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              Switch(
                                value: s.visible,
                                onChanged: service.busy
                                    ? null
                                    : (v) => run(
                                        () => service.setVisible(s.id, v),
                                      ),
                              ),
                            ],
                          ),
                          Text(
                            '${s.events.length} 条日程 · ${s.visible ? '显示中' : '已隐藏'}',
                          ),
                          Text(
                            '上次成功更新：${s.lastSuccess == null ? '尚未更新' : _dateTime(s.lastSuccess!.toLocal())}',
                          ),
                          if (s.message != null) Text(s.message!),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton.icon(
                                onPressed: service.busy
                                    ? null
                                    : () => run(
                                        () => service.refresh(
                                          id: s.id,
                                          force: true,
                                        ),
                                      ),
                                icon: const Icon(Icons.refresh),
                                label: const Text('刷新'),
                              ),
                              TextButton.icon(
                                onPressed: service.busy
                                    ? null
                                    : () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: Text('移除“${s.name}”？'),
                                            content: const Text(
                                              '将移除此订阅的本机缓存和个人备注。',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('取消'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('移除'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await run(() => service.remove(s.id));
                                        }
                                      },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('移除'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: service.busy
                ? null
                : () => run(() => service.refresh(force: true)),
            child: const Text('全部刷新'),
          ),
          FilledButton.icon(
            onPressed: service.busy || service.storageError != null
                ? null
                : () => showDialog<void>(
                    context: context,
                    builder: (_) => _AddSubscription(service: service),
                  ),
            icon: const Icon(Icons.add),
            label: const Text('添加订阅'),
          ),
        ],
      );
    },
  );
}

class _AddSubscription extends StatefulWidget {
  const _AddSubscription({required this.service});
  final SubscriptionService service;
  @override
  State<_AddSubscription> createState() => _AddSubscriptionState();
}

class _AddSubscriptionState extends State<_AddSubscription> {
  final name = TextEditingController();
  final url = TextEditingController();
  SubscriptionPreview? preview;
  String? error;
  bool busy = false;
  Future<void> act(bool save) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (save) {
        await widget.service.add(name.text, preview!);
        if (mounted) Navigator.pop(context);
      } else {
        final result = await widget.service.preview(url.text);
        if (mounted) setState(() => preview = result);
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message.toString()
              : '操作失败，请检查网络或磁盘空间',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加日历订阅'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              enabled: !busy,
              decoration: const InputDecoration(labelText: '名称，例如 HKU 课表'),
            ),
            TextField(
              controller: url,
              enabled: !busy,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'HTTPS 日历订阅地址'),
              onChanged: (_) => setState(() => preview = null),
            ),
            const SizedBox(height: 12),
            const Text('订阅地址与课程保存在本机，不参与云同步。'),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (preview != null) ...[
              const SizedBox(height: 12),
              Text(
                '读取到 ${preview!.events.where((e) => !e.cancelled).length} 条日程',
              ),
              if (preview!.events.isEmpty) const Text('目前为空，保存订阅后仍会继续刷新。'),
              for (final e
                  in preview!.events.where((e) => !e.cancelled).take(5))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${_dateTime(e.start)}\n${e.title}${e.location.isEmpty ? '' : '\n${e.location}'}',
                  ),
                ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: busy ? null : () => act(preview != null),
        child: Text(preview == null ? '读取预览' : '保存订阅'),
      ),
    ],
  );
  @override
  void dispose() {
    name.dispose();
    url.dispose();
    super.dispose();
  }
}

String _dateTime(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class SubscriptionDayList extends StatelessWidget {
  const SubscriptionDayList({
    super.key,
    required this.service,
    required this.day,
    required this.isCompleted,
    required this.onCompletionChanged,
  });
  final SubscriptionService service;
  final DateTime day;
  final bool Function(SubscriptionOccurrence occurrence) isCompleted;
  final Future<void> Function(SubscriptionOccurrence occurrence, bool completed)
  onCompletionChanged;
  @override
  Widget build(BuildContext context) {
    final events = service.eventsOn(day);
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: events.length,
      itemBuilder: (context, i) {
        final item = events[i];
        final completed = isCompleted(item);
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: SizedBox(
            width: 72,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.school_outlined, color: Color(item.source.color)),
                Checkbox(
                  value: completed,
                  onChanged: (value) =>
                      onCompletionChanged(item, value ?? false),
                ),
              ],
            ),
          ),
          title: Text(
            '${item.event.timeLabel}  ${item.event.title}',
            style: TextStyle(
              color: completed ? const Color(0xFF9AA1A8) : null,
              decoration: completed
                  ? TextDecoration.lineThrough
                  : TextDecoration.none,
            ),
          ),
          subtitle: Text(
            [
              item.source.name,
              if (item.event.location.isNotEmpty) item.event.location,
              if (item.event.missing) '来源暂未返回此课次，请核对',
              if (item.note.isNotEmpty) '备注：${item.note}',
            ].join(' · '),
          ),
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => _EventDetails(service: service, item: item),
          ),
        );
      },
    );
  }
}

class _EventDetails extends StatefulWidget {
  const _EventDetails({required this.service, required this.item});
  final SubscriptionService service;
  final SubscriptionOccurrence item;
  @override
  State<_EventDetails> createState() => _EventDetailsState();
}

class _EventDetailsState extends State<_EventDetails> {
  late final note = TextEditingController(text: widget.item.note);
  bool busy = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final e = widget.item.event;
    return AlertDialog(
      title: Text(e.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.item.source.name} · 香港时间'),
              Text(
                e.allDay
                    ? '${e.start.year}-${e.start.month}-${e.start.day} · 全天'
                    : '${_dateTime(e.start)} — ${_dateTime(e.end)}',
              ),
              if (e.location.isNotEmpty) SelectableText(e.location),
              if (e.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SelectableText(e.description),
                ),
              if (e.missing) const Text('本次来源未返回此日程，当前显示缓存内容，请与学校核对。'),
              TextField(
                controller: note,
                enabled: !busy,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: '个人备注',
                  helperText: '刷新课程时保留',
                ),
              ),
              if (error != null) Text(error!),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await widget.service.saveNote(
                      widget.item.source.id,
                      e.key,
                      note.text,
                    );
                    if (context.mounted) Navigator.pop(context);
                  } catch (_) {
                    if (mounted) setState(() => error = '备注未保存，请稍后重试');
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
          child: const Text('保存备注'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }
}
