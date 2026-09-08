import 'dart:convert';
import 'dart:io';

import 'package:baby_gallery/features/upload/upload_models.dart';
import 'package:baby_gallery/features/upload/upload_queue_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory testDirectory;
  late Directory storageDirectory;
  late File sourceFile;
  late UploadQueueStorage storage;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'baby-gallery-queue-',
    );
    storageDirectory = Directory(
      '${testDirectory.path}${Platform.pathSeparator}storage',
    );
    sourceFile = File(
      '${testDirectory.path}${Platform.pathSeparator}selected.jpg',
    );
    await sourceFile.writeAsBytes(const [1, 2, 3]);
    storage = UploadQueueStorage(storageDirectory);
  });

  tearDown(() async {
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test('선택 원본을 content hash 경로에 보관한다', () async {
    final retained = await storage.retainSource(_preparedUpload(sourceFile));

    expect(retained.source.path, isNot(sourceFile.path));
    expect(retained.source.fileName, '첫 사진.jpg');
    expect(await File(retained.source.path).readAsBytes(), [1, 2, 3]);
    expect(await sourceFile.readAsBytes(), [1, 2, 3]);
    expect(retained.source.path, endsWith('a' * 64));
  });

  test('이미 보관된 같은 크기의 파일을 재사용한다', () async {
    final first = await storage.retainSource(_preparedUpload(sourceFile));
    await sourceFile.writeAsBytes(const [9, 9, 9]);

    final second = await storage.retainSource(_preparedUpload(sourceFile));

    expect(second.source.path, first.source.path);
    expect(await File(second.source.path).readAsBytes(), [1, 2, 3]);
  });

  test('업로드 작업을 저장하고 관리 경로로 복구한다', () async {
    final retained = await storage.retainSource(_preparedUpload(sourceFile));
    final jobs = [
      UploadJob(
        upload: retained,
        status: UploadJobStatus.uploading,
        sentBytes: 2,
        errorMessage: '이전 오류',
      ),
    ];

    await storage.save(jobs);
    final restored = await storage.load();

    expect(restored, hasLength(1));
    expect(restored.single.id, 'a' * 64);
    expect(restored.single.upload.source.path, retained.source.path);
    expect(restored.single.upload.source.fileName, '첫 사진.jpg');
    expect(restored.single.status, UploadJobStatus.uploading);
    expect(restored.single.sentBytes, 2);
    expect(restored.single.errorMessage, '이전 오류');
  });

  test('교체 중 주 파일이 없으면 백업 대기열을 복구한다', () async {
    await storageDirectory.create(recursive: true);
    final backup = File(
      '${storageDirectory.path}${Platform.pathSeparator}queue.json.backup',
    );
    await backup.writeAsString(
      jsonEncode({
        'version': 1,
        'jobs': [
          UploadJob(
            upload: _preparedUpload(sourceFile),
            status: UploadJobStatus.pending,
          ).toJson(),
        ],
      }),
    );

    final restored = await storage.load();

    expect(restored.single.status, UploadJobStatus.pending);
    expect(restored.single.upload.source.path, endsWith('a' * 64));
  });

  test('완료한 업로드의 관리 원본을 제거한다', () async {
    final retained = await storage.retainSource(_preparedUpload(sourceFile));

    await storage.removeSource(retained.contentHash);

    expect(await File(retained.source.path).exists(), isFalse);
  });

  test('경로로 사용할 수 없는 해시를 거부한다', () async {
    final upload = PreparedUpload(
      source: LocalUploadFile(path: sourceFile.path, fileName: 'photo.jpg'),
      fileSize: 3,
      contentHash: '../outside',
      existingMediaId: null,
    );

    expect(() => storage.retainSource(upload), throwsFormatException);
    expect(() => storage.removeSource('../outside'), throwsFormatException);
  });
}

PreparedUpload _preparedUpload(File source) {
  return PreparedUpload(
    source: LocalUploadFile(path: source.path, fileName: '첫 사진.jpg'),
    fileSize: 3,
    contentHash: 'a' * 64,
    existingMediaId: null,
  );
}
