import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zrk_calendar/services/todo_attachment_service.dart';

void main() {
  test('照片复制到应用目录，重新打开后仍可读取，删除不影响原图', () async {
    final directory = await Directory.systemTemp.createTemp(
      'todo-attachment-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final appDirectory = Directory('${directory.path}/app');
    final original = File('${directory.path}/original.jpg');
    await original.writeAsBytes([1, 2, 3, 4]);
    final manifest = File('${appDirectory.path}/todo_attachments.json');
    final service = TodoAttachmentService(
      rootDirectory: appDirectory,
      manifestFile: manifest,
    );
    addTearDown(service.dispose);
    await service.initialize();

    final added = await service.addFromPaths('todo-a', [original.path]);

    expect(added, hasLength(1));
    expect(await original.exists(), isTrue);
    expect(await service.fileFor(added.single).readAsBytes(), [1, 2, 3, 4]);

    final reopened = TodoAttachmentService(
      rootDirectory: appDirectory,
      manifestFile: manifest,
    );
    addTearDown(reopened.dispose);
    await reopened.initialize();
    final persisted = reopened.attachmentsForTodo('todo-a');
    expect(persisted, hasLength(1));

    await reopened.remove(persisted.single.id);
    expect(reopened.attachmentsForTodo('todo-a'), isEmpty);
    expect(await original.exists(), isTrue);
    expect(await reopened.fileFor(persisted.single).exists(), isFalse);
  });

  test('限制附件数量并拒绝非图片扩展名', () async {
    final directory = await Directory.systemTemp.createTemp(
      'todo-attachment-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = TodoAttachmentService(rootDirectory: directory);
    addTearDown(service.dispose);
    await service.initialize();
    final images = <String>[];
    for (var index = 0; index < 6; index++) {
      final file = File('${directory.path}/image-$index.jpg');
      await file.writeAsBytes([index + 1]);
      images.add(file.path);
    }

    await expectLater(
      service.addFromPaths('todo-a', images),
      throwsFormatException,
    );
    final textFile = File('${directory.path}/notes.txt');
    await textFile.writeAsString('not an image');
    await expectLater(
      service.addFromPaths('todo-a', [textFile.path]),
      throwsFormatException,
    );
    expect(service.attachmentsForTodo('todo-a'), isEmpty);
  });

  test('损坏的附件清单不会被覆盖', () async {
    final directory = await Directory.systemTemp.createTemp(
      'todo-attachment-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manifest = File('${directory.path}/todo_attachments.json');
    await manifest.writeAsString('broken');
    final service = TodoAttachmentService(
      rootDirectory: directory,
      manifestFile: manifest,
    );
    addTearDown(service.dispose);

    await service.initialize();

    expect(service.storageError, isNotNull);
    await expectLater(
      service.addFromPaths('todo-a', const []),
      throwsFormatException,
    );
    expect(await manifest.readAsString(), 'broken');
  });
}
