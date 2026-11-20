import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class TodoAttachment {
  const TodoAttachment({
    required this.id,
    required this.todoId,
    required this.fileName,
    required this.originalName,
    required this.createdAt,
  });

  final String id;
  final String todoId;
  final String fileName;
  final String originalName;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'todoId': todoId,
    'fileName': fileName,
    'originalName': originalName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory TodoAttachment.fromJson(Map<String, dynamic> json) {
    final fileName = json['fileName'] as String;
    if (p.basename(fileName) != fileName) {
      throw const FormatException('附件文件名无效');
    }
    return TodoAttachment(
      id: json['id'] as String,
      todoId: json['todoId'] as String,
      fileName: fileName,
      originalName: json['originalName'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }
}

class TodoAttachmentService extends ChangeNotifier {
  TodoAttachmentService({this.rootDirectory, this.manifestFile, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  static const maxAttachmentsPerTodo = 5;
  static const maxFileBytes = 10 * 1024 * 1024;
  static const supportedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.heic',
    '.heif',
  };

  final Directory? rootDirectory;
  final File? manifestFile;
  final Uuid _uuid;
  final List<TodoAttachment> _attachments = [];
  Directory? _resolvedRoot;
  File? _resolvedManifest;
  bool _isReady = false;
  bool _isDisposed = false;
  String? storageError;

  Future<void> initialize() async {
    if (_isReady) return;
    final supportDirectory = rootDirectory == null
        ? await getApplicationSupportDirectory()
        : null;
    final appDirectory =
        rootDirectory ??
        Directory(p.join(supportDirectory!.path, 'zrk_calendar'));
    _resolvedRoot = Directory(p.join(appDirectory.path, 'todo_attachments'));
    _resolvedManifest =
        manifestFile ??
        File(p.join(appDirectory.path, 'todo_attachments.json'));
    try {
      if (await _resolvedManifest!.exists()) {
        final data =
            jsonDecode(await _resolvedManifest!.readAsString())
                as Map<String, dynamic>;
        if (data['version'] != 1 || data['attachments'] is! List) {
          throw const FormatException('附件存储版本不兼容');
        }
        _attachments.addAll(
          (data['attachments'] as List).map(
            (item) =>
                TodoAttachment.fromJson(Map<String, dynamic>.from(item as Map)),
          ),
        );
      }
      _isReady = true;
    } catch (_) {
      storageError = '无法读取待办附件，原文件已保留。';
    }
    _notify();
  }

  List<TodoAttachment> attachmentsForTodo(String todoId) {
    return _attachments.where((item) => item.todoId == todoId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  File fileFor(TodoAttachment attachment) {
    return File(p.join(_resolvedRoot!.path, attachment.fileName));
  }

  Future<List<TodoAttachment>> addFromPaths(
    String todoId,
    Iterable<String> paths,
  ) async {
    _ensureReady();
    final sourceFiles = paths.map(File.new).toList(growable: false);
    if (sourceFiles.isEmpty) return const [];
    final existingCount = attachmentsForTodo(todoId).length;
    if (existingCount + sourceFiles.length > maxAttachmentsPerTodo) {
      throw const FormatException('每个待办最多添加 5 张照片');
    }

    final createdFiles = <File>[];
    final createdAttachments = <TodoAttachment>[];
    try {
      await _resolvedRoot!.create(recursive: true);
      for (final source in sourceFiles) {
        final extension = p.extension(source.path).toLowerCase();
        if (!supportedExtensions.contains(extension)) {
          throw const FormatException('仅支持常见的图片文件');
        }
        if (!await source.exists()) {
          throw const FormatException('所选照片已不存在');
        }
        final size = await source.length();
        if (size <= 0 || size > maxFileBytes) {
          throw const FormatException('每张照片必须小于 10 MB');
        }
        final id = _uuid.v4();
        final fileName = '$id$extension';
        final destination = File(p.join(_resolvedRoot!.path, fileName));
        final temporary = File('${destination.path}.tmp');
        await source.copy(temporary.path);
        await temporary.rename(destination.path);
        createdFiles.add(destination);
        createdAttachments.add(
          TodoAttachment(
            id: id,
            todoId: todoId,
            fileName: fileName,
            originalName: p.basename(source.path),
            createdAt: DateTime.now().toUtc(),
          ),
        );
      }
      _attachments.addAll(createdAttachments);
      await _save();
      storageError = null;
      _notify();
      return List.unmodifiable(createdAttachments);
    } catch (_) {
      _attachments.removeWhere(
        (item) => createdAttachments.any((created) => created.id == item.id),
      );
      for (final file in createdFiles) {
        if (await file.exists()) await file.delete();
      }
      rethrow;
    }
  }

  Future<void> remove(String attachmentId) async {
    _ensureReady();
    final index = _attachments.indexWhere((item) => item.id == attachmentId);
    if (index < 0) return;
    final attachment = _attachments.removeAt(index);
    final file = fileFor(attachment);
    final stagedFile = File('${file.path}.deleting');
    try {
      if (await file.exists()) await file.rename(stagedFile.path);
      await _save();
      if (await stagedFile.exists()) await stagedFile.delete();
      storageError = null;
      _notify();
    } catch (_) {
      _attachments.insert(index, attachment);
      if (await stagedFile.exists()) await stagedFile.rename(file.path);
      storageError = '照片附件删除失败，请稍后重试。';
      _notify();
      rethrow;
    }
  }

  void _ensureReady() {
    if (!_isReady) throw const FormatException('待办附件尚不可用');
  }

  Future<void> _save() async {
    await _resolvedManifest!.parent.create(recursive: true);
    final temporary = File('${_resolvedManifest!.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'attachments': _attachments.map((item) => item.toJson()).toList(),
      }),
      flush: true,
    );
    await temporary.rename(_resolvedManifest!.path);
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
