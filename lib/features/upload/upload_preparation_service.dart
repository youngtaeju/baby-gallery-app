import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'upload_models.dart';
import 'upload_repository.dart';

const int maxUploadSelectionCount = 200;

class UploadPreparationService {
  UploadPreparationService(this._repository);

  final UploadRepository _repository;

  Future<List<PreparedUpload>> prepare(List<LocalUploadFile> sources) async {
    if (sources.length > maxUploadSelectionCount) {
      throw ArgumentError.value(
        sources.length,
        'sources',
        '한 번에 최대 $maxUploadSelectionCount개까지 업로드할 수 있습니다.',
      );
    }

    if (sources.isEmpty) {
      return const [];
    }

    // NAS 업로드 전에 로컬 저장소를 순차 접근해 여러 대용량 파일의 I/O 경합 방지.
    final files = await Isolate.run(() => _hashFiles(sources));

    final lookup = await _repository.lookup(
      files.map((file) => file.contentHash).toList(growable: false),
    );

    if (lookup.length != files.length) {
      throw const FormatException('중복 조회 응답의 항목 수가 올바르지 않습니다.');
    }

    return List.generate(files.length, (index) {
      final file = files[index];
      final result = lookup[index];

      if (result.hash != file.contentHash) {
        throw const FormatException('중복 조회 응답의 해시 순서가 올바르지 않습니다.');
      }

      return PreparedUpload(
        source: file.source,
        fileSize: file.fileSize,
        contentHash: file.contentHash,
        existingMediaId: result.mediaId,
      );
    }, growable: false);
  }
}

Future<List<_HashedUploadFile>> _hashFiles(
  List<LocalUploadFile> sources,
) async {
  final files = <_HashedUploadFile>[];

  for (final source in sources) {
    final file = File(source.path);
    final fileSize = await file.length();
    final digest = await sha256.bind(file.openRead()).first;

    files.add(
      _HashedUploadFile(
        source: source,
        fileSize: fileSize,
        contentHash: digest.toString(),
      ),
    );
  }

  return files;
}

class _HashedUploadFile {
  const _HashedUploadFile({
    required this.source,
    required this.fileSize,
    required this.contentHash,
  });

  final LocalUploadFile source;
  final int fileSize;
  final String contentHash;
}

final uploadPreparationServiceProvider = Provider<UploadPreparationService>((
  ref,
) {
  return UploadPreparationService(ref.watch(uploadRepositoryProvider));
});
