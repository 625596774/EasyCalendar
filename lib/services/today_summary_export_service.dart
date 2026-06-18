import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../features/calendar/domain/daily_summary.dart';
import 'daily_summary_service.dart';

typedef TodaySummaryDirectoryProvider = Future<Directory> Function();

class TodaySummaryExportResult {
  const TodaySummaryExportResult._({
    required this.isSuccess,
    this.path,
    this.error,
  });

  factory TodaySummaryExportResult.success(String path) {
    return TodaySummaryExportResult._(isSuccess: true, path: path);
  }

  factory TodaySummaryExportResult.failure(String error) {
    return TodaySummaryExportResult._(isSuccess: false, error: error);
  }

  final bool isSuccess;
  final String? path;
  final String? error;
}

class TodaySummaryExportService {
  TodaySummaryExportService({
    required DailySummaryService dailySummaryService,
    TodaySummaryDirectoryProvider? directoryProvider,
  }) : this._(dailySummaryService, directoryProvider ?? _defaultDirectory);

  TodaySummaryExportService._(
    this._dailySummaryService,
    this._directoryProvider,
  );

  static const fileName = 'today_summary.json';

  final DailySummaryService _dailySummaryService;
  final TodaySummaryDirectoryProvider _directoryProvider;
  Future<void> _exportQueue = Future.value();
  int _tempFileSequence = 0;

  Future<TodaySummaryExportResult> exportToday({DateTime? now}) async {
    try {
      final summary = await _dailySummaryService.buildForDate(
        now ?? DateTime.now(),
      );
      return exportSummary(summary);
    } on Object catch (error) {
      return TodaySummaryExportResult.failure(_safeError(error));
    }
  }

  Future<TodaySummaryExportResult> exportSummary(
    DailySummary summary, {
    String outputFileName = fileName,
  }) {
    final exportTask = _exportQueue.then(
      (_) => _writeSummary(summary, outputFileName: outputFileName),
    );
    _exportQueue = exportTask.then<void>((_) {}, onError: (_) {});
    return exportTask;
  }

  Future<TodaySummaryExportResult> _writeSummary(
    DailySummary summary, {
    required String outputFileName,
  }) async {
    try {
      final directory = await _directoryProvider();
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, outputFileName));
      await file.parent.create(recursive: true);
      final tempFile = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.'
        '${_tempFileSequence++}.tmp',
      );
      await tempFile.parent.create(recursive: true);
      final payload = const JsonEncoder.withIndent(
        '  ',
      ).convert(summary.toJson());

      await tempFile.writeAsString('$payload\n', flush: true);
      try {
        if (await file.exists()) {
          await file.delete();
        }
        await tempFile.rename(file.path);
      } on FileSystemException {
        await file.parent.create(recursive: true);
        await file.writeAsString('$payload\n', flush: true);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }
      await _tryWriteSharedSummary(payload, outputFileName: outputFileName);
      return TodaySummaryExportResult.success(file.path);
    } on Object catch (error) {
      return TodaySummaryExportResult.failure(_safeError(error));
    }
  }

  Future<void> _tryWriteSharedSummary(
    String payload, {
    required String outputFileName,
  }) async {
    if (outputFileName != fileName) {
      return;
    }

    try {
      final directory = _sharedDirectory();
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, fileName));
      await _atomicWrite(file, payload);
    } on Object catch (error) {
      debugPrint('today_summary 共享导出失败：${_safeError(error)}');
    }
  }

  Future<void> _atomicWrite(File file, String payload) async {
    await file.parent.create(recursive: true);
    final tempFile = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.'
      '${_tempFileSequence++}.tmp',
    );
    await tempFile.parent.create(recursive: true);
    await tempFile.writeAsString('$payload\n', flush: true);
    try {
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
    } on FileSystemException {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  static Future<Directory> _defaultDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'zrk_calendar', 'widget'));
  }

  static Directory _sharedDirectory() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw const FileSystemException('HOME is not available');
    }
    return Directory(
      p.join(
        home,
        'Library',
        'Application Support',
        'ZRKShared',
        'EasyCalendar',
      ),
    );
  }

  static String _safeError(Object error) => error.runtimeType.toString();
}
