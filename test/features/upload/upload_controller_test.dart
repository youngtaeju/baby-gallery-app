import 'dart:async';
import 'dart:io';

import 'package:baby_gallery/core/api_exception.dart';
import 'package:baby_gallery/features/upload/upload_controller.dart';
import 'package:baby_gallery/features/upload/upload_models.dart';
import 'package:baby_gallery/features/upload/upload_preparation_service.dart';
import 'package:baby_gallery/features/upload/upload_queue_storage.dart';
import 'package:baby_gallery/features/upload/upload_repository.dart';
import 'package:baby_gallery/features/upload/upload_transfer_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory testDirectory;
  late UploadQueueStorage storage;

  setUp(() async {
    testDirectory = await Directory.systemTemp.createTemp(
      'baby-gallery-controller-',
    );
    storage = UploadQueueStorage(
      Directory('${testDirectory.path}${Platform.pathSeparator}queue'),
    );
  });

  tearDown(() async {
    if (await testDirectory.exists()) {
      await testDirectory.delete(recursive: true);
    }
  });

  test('준비한 신규 파일을 보관하고 순차 업로드한다', () async {
    final first = await _source(testDirectory, 'first.jpg', [1, 2, 3]);
    final second = await _source(testDirectory, 'second.jpg', [4, 5]);
    final uploads = [
      _upload(first, 'a', size: 3),
      _upload(second, 'b', size: 2),
    ];
    final transfer = _FakeTransferService();
    final container = _container(
      storage: storage,
      preparation: _FakePreparationService(uploads),
      transfer: transfer,
    );
    addTearDown(container.dispose);
    await container.read(uploadControllerProvider.future);

    await container.read(uploadControllerProvider.notifier).addFiles([
      uploads[0].source,
      uploads[1].source,
    ]);
    await _waitFor(
      container,
      (state) =>
          state.jobs.every((job) => job.status == UploadJobStatus.completed),
    );

    final state = container.read(uploadControllerProvider).requireValue;
    expect(state.jobs.map((job) => job.mediaId), [1, 2]);
    expect(transfer.maxConcurrent, 1);
    expect(transfer.uploadedHashes, ['a' * 64, 'b' * 64]);
    expect(await storage.load(), isEmpty);
    expect(await File(state.jobs[0].upload.source.path).exists(), isFalse);
    expect(await File(state.jobs[1].upload.source.path).exists(), isFalse);
  });

  test('서버 중복 파일은 보관하거나 전송하지 않고 완료 처리한다', () async {
    final source = await _source(testDirectory, 'duplicate.jpg', [1]);
    final upload = _upload(source, 'c', size: 1, existingMediaId: 17);
    final transfer = _FakeTransferService();
    final container = _container(
      storage: storage,
      preparation: _FakePreparationService([upload]),
      transfer: transfer,
    );
    addTearDown(container.dispose);
    await container.read(uploadControllerProvider.future);

    await container.read(uploadControllerProvider.notifier).addFiles([
      upload.source,
    ]);

    final job = container
        .read(uploadControllerProvider)
        .requireValue
        .jobs
        .single;
    expect(job.status, UploadJobStatus.completed);
    expect(job.mediaId, 17);
    expect(job.isDuplicate, isTrue);
    expect(transfer.uploadedHashes, isEmpty);
    expect(await source.exists(), isTrue);
  });

  test('실패한 작업을 유지하고 재시도한다', () async {
    final source = await _source(testDirectory, 'retry.jpg', [1, 2]);
    final upload = _upload(source, 'd', size: 2);
    final transfer = _FakeTransferService(failuresBeforeSuccess: 1);
    final container = _container(
      storage: storage,
      preparation: _FakePreparationService([upload]),
      transfer: transfer,
    );
    addTearDown(container.dispose);
    await container.read(uploadControllerProvider.future);

    await container.read(uploadControllerProvider.notifier).addFiles([
      upload.source,
    ]);
    await _waitFor(
      container,
      (state) => state.jobs.single.status == UploadJobStatus.failed,
    );

    var job = container.read(uploadControllerProvider).requireValue.jobs.single;
    expect(job.errorMessage, '일시적인 업로드 오류');
    expect(await storage.load(), hasLength(1));

    await container.read(uploadControllerProvider.notifier).retry(job.id);
    await _waitFor(
      container,
      (state) => state.jobs.single.status == UploadJobStatus.completed,
    );

    job = container.read(uploadControllerProvider).requireValue.jobs.single;
    expect(job.mediaId, 2);
    expect(transfer.uploadedHashes, ['d' * 64, 'd' * 64]);
    expect(await storage.load(), isEmpty);
  });

  test('앱 종료 당시 업로드 중인 작업을 자동 재개한다', () async {
    final source = await _source(testDirectory, 'resume.jpg', [1, 2, 3]);
    final retained = await storage.retainSource(_upload(source, 'e', size: 3));
    await storage.save([
      UploadJob(
        upload: retained,
        status: UploadJobStatus.uploading,
        sentBytes: 1,
      ),
    ]);
    final transfer = _FakeTransferService();
    final container = _container(
      storage: storage,
      preparation: _FakePreparationService(const []),
      transfer: transfer,
    );
    addTearDown(container.dispose);

    await container.read(uploadControllerProvider.future);
    await _waitFor(
      container,
      (state) => state.jobs.single.status == UploadJobStatus.completed,
    );

    expect(transfer.uploadedHashes, ['e' * 64]);
    expect(await storage.load(), isEmpty);
  });

  test('완료 또는 실패한 작업을 목록에서 제거한다', () async {
    final source = await _source(testDirectory, 'remove.jpg', [1]);
    final retained = await storage.retainSource(_upload(source, 'f', size: 1));
    await storage.save([
      UploadJob(upload: retained, status: UploadJobStatus.failed),
    ]);
    final container = _container(
      storage: storage,
      preparation: _FakePreparationService(const []),
      transfer: _FakeTransferService(),
    );
    addTearDown(container.dispose);
    await container.read(uploadControllerProvider.future);

    await container.read(uploadControllerProvider.notifier).remove('f' * 64);

    expect(container.read(uploadControllerProvider).requireValue.jobs, isEmpty);
    expect(await File(retained.source.path).exists(), isFalse);
    expect(await storage.load(), isEmpty);
  });

  test('업로드 중 추가한 파일을 기존 작업 상태와 함께 유지한다', () async {
    final first = await _source(testDirectory, 'active.jpg', [1]);
    final second = await _source(testDirectory, 'added.jpg', [2]);
    final firstUpload = _upload(first, '1', size: 1);
    final secondUpload = _upload(second, '2', size: 1);
    final preparation = _QueuedPreparationService([
      [firstUpload],
      [secondUpload],
    ]);
    final transfer = _ControlledTransferService();
    final container = _container(
      storage: storage,
      preparation: preparation,
      transfer: transfer,
    );
    addTearDown(container.dispose);
    await container.read(uploadControllerProvider.future);

    await container.read(uploadControllerProvider.notifier).addFiles([
      firstUpload.source,
    ]);
    await transfer.started.future;
    final addSecond = container
        .read(uploadControllerProvider.notifier)
        .addFiles([secondUpload.source]);
    transfer.complete();
    await addSecond;
    await _waitFor(
      container,
      (state) =>
          state.jobs.length == 2 &&
          state.jobs.every((job) => job.status == UploadJobStatus.completed),
    );

    final jobs = container.read(uploadControllerProvider).requireValue.jobs;
    expect(jobs.map((job) => job.id), ['1' * 64, '2' * 64]);
    expect(await storage.load(), isEmpty);
  });
}

ProviderContainer _container({
  required UploadQueueStorage storage,
  required UploadPreparationService preparation,
  required UploadTransferService transfer,
}) {
  return ProviderContainer(
    overrides: [
      uploadQueueStorageProvider.overrideWith((ref) async => storage),
      uploadPreparationServiceProvider.overrideWithValue(preparation),
      uploadTransferServiceProvider.overrideWith((ref) async => transfer),
    ],
  );
}

Future<void> _waitFor(
  ProviderContainer container,
  bool Function(UploadQueueState state) predicate,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final value = container.read(uploadControllerProvider).value;

    if (value != null && predicate(value)) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  fail('업로드 상태 변경을 기다리는 중 시간이 초과됐습니다.');
}

Future<File> _source(Directory directory, String name, List<int> bytes) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes);
  return file;
}

PreparedUpload _upload(
  File source,
  String hashCharacter, {
  required int size,
  int? existingMediaId,
}) {
  return PreparedUpload(
    source: LocalUploadFile(
      path: source.path,
      fileName: source.uri.pathSegments.last,
    ),
    fileSize: size,
    contentHash: hashCharacter * 64,
    existingMediaId: existingMediaId,
  );
}

class _FakePreparationService extends UploadPreparationService {
  _FakePreparationService(this.uploads) : super(UploadRepository(Dio()));

  final List<PreparedUpload> uploads;

  @override
  Future<List<PreparedUpload>> prepare(List<LocalUploadFile> sources) async {
    return uploads;
  }
}

class _QueuedPreparationService extends UploadPreparationService {
  _QueuedPreparationService(this.results) : super(UploadRepository(Dio()));

  final List<List<PreparedUpload>> results;
  int calls = 0;

  @override
  Future<List<PreparedUpload>> prepare(List<LocalUploadFile> sources) async {
    return results[calls++];
  }
}

class _FakeTransferService extends UploadTransferService {
  _FakeTransferService({this.failuresBeforeSuccess = 0})
    : super(_UnusedTransport(), UploadRepository(Dio()));

  int failuresBeforeSuccess;
  int active = 0;
  int maxConcurrent = 0;
  int attempts = 0;
  final List<String> uploadedHashes = [];

  @override
  Future<UploadCommitResult> transfer(
    PreparedUpload upload, {
    UploadProgressCallback? onProgress,
  }) async {
    uploadedHashes.add(upload.contentHash);
    active++;
    maxConcurrent = active > maxConcurrent ? active : maxConcurrent;
    attempts++;

    try {
      onProgress?.call(upload.fileSize ~/ 2, upload.fileSize);
      await Future<void>.delayed(Duration.zero);

      if (attempts <= failuresBeforeSuccess) {
        throw const ApiException('일시적인 업로드 오류');
      }

      onProgress?.call(upload.fileSize, upload.fileSize);
      return UploadCommitResult(mediaId: attempts, isDuplicate: false);
    } finally {
      active--;
    }
  }
}

class _ControlledTransferService extends UploadTransferService {
  _ControlledTransferService()
    : super(_UnusedTransport(), UploadRepository(Dio()));

  final Completer<void> started = Completer<void>();
  final Completer<void> _release = Completer<void>();
  int attempts = 0;

  void complete() => _release.complete();

  @override
  Future<UploadCommitResult> transfer(
    PreparedUpload upload, {
    UploadProgressCallback? onProgress,
  }) async {
    attempts++;

    if (attempts == 1) {
      started.complete();
      await _release.future;
    }

    onProgress?.call(upload.fileSize, upload.fileSize);
    return UploadCommitResult(mediaId: attempts, isDuplicate: false);
  }
}

class _UnusedTransport implements UploadTransport {
  @override
  Future<Uri> send(
    PreparedUpload upload, {
    UploadProgressCallback? onProgress,
  }) {
    throw UnimplementedError();
  }
}
