import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'upload_models.dart';

class UploadQueueStorage {
  UploadQueueStorage(this.rootDirectory);

  static const int _schemaVersion = 1;

  final Directory rootDirectory;

  Directory get _sourcesDirectory =>
      Directory('${rootDirectory.path}${Platform.pathSeparator}sources');

  File get _queueFile =>
      File('${rootDirectory.path}${Platform.pathSeparator}queue.json');

  File get _nextQueueFile => File('${_queueFile.path}.next');

  File get _backupQueueFile => File('${_queueFile.path}.backup');

  Future<PreparedUpload> retainSource(PreparedUpload upload) async {
    _validateHash(upload.contentHash);

    if (!upload.needsUpload) {
      return upload;
    }

    await _sourcesDirectory.create(recursive: true);
    final retained = _sourceFile(upload.contentHash);

    if (await retained.exists() && await retained.length() == upload.fileSize) {
      return _withSource(upload, retained.path);
    }

    final temporary = File('${retained.path}.part');

    if (await temporary.exists()) {
      await temporary.delete();
    }

    await File(upload.source.path).copy(temporary.path);

    if (await temporary.length() != upload.fileSize) {
      await temporary.delete();
      throw const FileSystemException('보관한 업로드 파일의 크기가 원본과 다릅니다.');
    }

    if (await retained.exists()) {
      await retained.delete();
    }

    await temporary.rename(retained.path);

    return _withSource(upload, retained.path);
  }

  Future<List<UploadJob>> load() async {
    final queueFile = await _readableQueueFile();

    if (queueFile == null) {
      return const [];
    }

    final decoded = jsonDecode(await queueFile.readAsString());

    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != _schemaVersion ||
        decoded['jobs'] is! List) {
      throw const FormatException('업로드 대기열 파일이 올바르지 않습니다.');
    }

    return (decoded['jobs'] as List<dynamic>)
        .map((value) {
          final json = value as Map<String, dynamic>;
          final contentHash = json['contentHash'] as String;
          _validateHash(contentHash);

          return UploadJob.fromJson(
            json,
            sourcePath: _sourceFile(contentHash).path,
          );
        })
        .toList(growable: false);
  }

  Future<void> save(List<UploadJob> jobs) async {
    await rootDirectory.create(recursive: true);
    final body = jsonEncode({
      'version': _schemaVersion,
      'jobs': jobs.map((job) => job.toJson()).toList(growable: false),
    });

    if (await _nextQueueFile.exists()) {
      await _nextQueueFile.delete();
    }

    await _nextQueueFile.writeAsString(body, flush: true);

    if (await _backupQueueFile.exists()) {
      await _backupQueueFile.delete();
    }

    if (await _queueFile.exists()) {
      await _queueFile.rename(_backupQueueFile.path);
    }

    await _nextQueueFile.rename(_queueFile.path);

    if (await _backupQueueFile.exists()) {
      await _backupQueueFile.delete();
    }
  }

  Future<void> removeSource(String contentHash) async {
    _validateHash(contentHash);
    final source = _sourceFile(contentHash);

    if (await source.exists()) {
      await source.delete();
    }
  }

  Future<File?> _readableQueueFile() async {
    if (await _queueFile.exists()) {
      return _queueFile;
    }

    if (await _backupQueueFile.exists()) {
      return _backupQueueFile;
    }

    return null;
  }

  File _sourceFile(String contentHash) =>
      File('${_sourcesDirectory.path}${Platform.pathSeparator}$contentHash');

  static PreparedUpload _withSource(PreparedUpload upload, String path) {
    return PreparedUpload(
      source: LocalUploadFile(path: path, fileName: upload.source.fileName),
      fileSize: upload.fileSize,
      contentHash: upload.contentHash,
      existingMediaId: upload.existingMediaId,
    );
  }

  static void _validateHash(String contentHash) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(contentHash)) {
      throw const FormatException('업로드 파일 해시가 올바르지 않습니다.');
    }
  }
}

final uploadQueueStorageProvider = FutureProvider<UploadQueueStorage>((
  ref,
) async {
  final supportDirectory = await getApplicationSupportDirectory();

  return UploadQueueStorage(
    Directory('${supportDirectory.path}${Platform.pathSeparator}upload-queue'),
  );
});
