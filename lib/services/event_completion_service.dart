import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../features/subscriptions/subscription_service.dart';
import '../shared/utils/date_utils.dart';

class EventCompletionService extends ChangeNotifier {
  EventCompletionService({this.file});

  final File? file;
  File? _resolvedFile;
  final Set<String> _completedKeys = {};
  bool _isReady = false;
  bool _isDisposed = false;
  String? storageError;

  Future<void> initialize() async {
    if (_isReady) return;
    _resolvedFile ??=
        file ??
        File(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'zrk_calendar',
            'event_completions.json',
          ),
        );
    try {
      if (await _resolvedFile!.exists()) {
        final data =
            jsonDecode(await _resolvedFile!.readAsString())
                as Map<String, dynamic>;
        if (data['version'] != 1 || data['completed'] is! List) {
          throw const FormatException('完成状态存储版本不兼容');
        }
        _completedKeys.addAll((data['completed'] as List).cast<String>());
      }
      _isReady = true;
    } catch (_) {
      storageError = '无法读取活动完成状态，原文件已保留。';
    }
    _notify();
  }

  bool isRecurringCompleted(String eventId, DateTime date) {
    return _completedKeys.contains(_recurringKey(eventId, date));
  }

  bool isSubscriptionCompleted(
    SubscriptionOccurrence occurrence,
    DateTime date,
  ) {
    return _completedKeys.contains(subscriptionKey(occurrence, date));
  }

  String subscriptionKey(SubscriptionOccurrence occurrence, DateTime date) {
    return 'subscription:${occurrence.source.id}:${occurrence.event.key}:${dateKey(date)}';
  }

  Future<void> setRecurringCompleted(
    String eventId,
    DateTime date,
    bool completed,
  ) {
    return _setCompleted(_recurringKey(eventId, date), completed);
  }

  Future<void> setSubscriptionCompleted(
    SubscriptionOccurrence occurrence,
    DateTime date,
    bool completed,
  ) {
    return _setCompleted(subscriptionKey(occurrence, date), completed);
  }

  String _recurringKey(String eventId, DateTime date) {
    return 'recurring:$eventId:${dateKey(date)}';
  }

  Future<void> _setCompleted(String key, bool completed) async {
    if (!_isReady) {
      throw const FormatException('活动完成状态尚不可用');
    }
    final wasCompleted = _completedKeys.contains(key);
    if (wasCompleted == completed) return;
    if (completed) {
      _completedKeys.add(key);
    } else {
      _completedKeys.remove(key);
    }
    _notify();
    try {
      await _save();
      storageError = null;
    } catch (_) {
      if (wasCompleted) {
        _completedKeys.add(key);
      } else {
        _completedKeys.remove(key);
      }
      storageError = '活动完成状态保存失败，请检查磁盘空间后重试。';
      _notify();
      rethrow;
    }
  }

  Future<void> _save() async {
    await _resolvedFile!.parent.create(recursive: true);
    final temporary = File('${_resolvedFile!.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'version': 1, 'completed': _completedKeys.toList()..sort()}),
      flush: true,
    );
    await temporary.rename(_resolvedFile!.path);
  }

  void _notify() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
