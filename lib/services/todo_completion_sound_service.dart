import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

class TodoCompletionSoundService {
  const TodoCompletionSoundService();

  void playCompleted() {
    unawaited(_playCompleted());
  }

  Future<void> _playCompleted() async {
    if (Platform.isLinux && await _tryPlayLinuxCompleteSound()) {
      return;
    }
    await _tryPlayFlutterAlert();
  }

  Future<bool> _tryPlayLinuxCompleteSound() async {
    try {
      final result = await Process.run('canberra-gtk-play', const [
        '--id',
        'complete',
        '--description',
        'EasyCalendar 待办完成',
      ]).timeout(const Duration(seconds: 2));
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<void> _tryPlayFlutterAlert() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } on Object {
      // 声音只是轻提示，播放失败不应影响待办状态。
    }
  }
}
