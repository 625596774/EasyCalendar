import 'dart:convert';
import 'dart:io';

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
  }) async {
    try {
      final directory = await _directoryProvider();
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, outputFileName));
      final tempFile = File('${file.path}.tmp');
      final payload = const JsonEncoder.withIndent(
        '  ',
      ).convert(summary.toJson());

      await tempFile.writeAsString('$payload\n');
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
      return TodaySummaryExportResult.success(file.path);
    } on Object catch (error) {
      return TodaySummaryExportResult.failure(_safeError(error));
    }
  }

  static Future<Directory> _defaultDirectory() async {
    final supportDirectory = await getApplicationSupportDirectory();
    return Directory(p.join(supportDirectory.path, 'zrk_calendar', 'widget'));
  }

  static String _safeError(Object error) => error.runtimeType.toString();
}
