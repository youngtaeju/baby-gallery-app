import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import 'upload_models.dart';
import 'upload_preparation_service.dart';
import 'upload_queue_storage.dart';
import 'upload_transfer_service.dart';

class UploadQueueState {
  UploadQueueState({
    required List<UploadJob> jobs,
    this.isPreparing = false,
    this.preparationError,
  }) : jobs = List.unmodifiable(jobs);

  final List<UploadJob> jobs;

  final bool isPreparing;

  final String? preparationError;

  bool get isUploading =>
      jobs.any((job) => job.status == UploadJobStatus.uploading);

  UploadQueueState copyWith({
    List<UploadJob>? jobs,
    bool? isPreparing,
    Object? preparationError = _unset,
  }) {
    return UploadQueueState(
      jobs: jobs ?? this.jobs,
      isPreparing: isPreparing ?? this.isPreparing,
      preparationError: identical(preparationError, _unset)
          ? this.preparationError
          : preparationError as String?,
    );
  }
}

class UploadController extends AsyncNotifier<UploadQueueState> {
  static const int _progressStep = 256 * 1024;

  bool _draining = false;
  Future<void> _writeTail = Future.value();

  @override
  Future<UploadQueueState> build() async {
    final storage = await ref.watch(uploadQueueStorageProvider.future);
    final restored = await storage.load();
    final jobs = restored
        .map((job) {
          if (job.status != UploadJobStatus.uploading) {
            return job;
          }

          return job.copyWith(
            status: UploadJobStatus.pending,
            errorMessage: null,
          );
        })
        .toList(growable: false);

    Timer.run(() {
      if (ref.mounted) {
        unawaited(_drain());
      }
    });

    return UploadQueueState(jobs: jobs);
  }

  Future<void> addFiles(List<LocalUploadFile> sources) async {
    final current = state.value;

    if (current == null || current.isPreparing || sources.isEmpty) {
      return;
    }

    state = AsyncData(
      current.copyWith(isPreparing: true, preparationError: null),
    );

    try {
      final prepared = await ref
          .read(uploadPreparationServiceProvider)
          .prepare(sources);
      final storage = await ref.read(uploadQueueStorageProvider.future);
      final additions = <UploadJob>[];
      final preparedHashes = <String>{};

      for (final upload in prepared) {
        if (!preparedHashes.add(upload.contentHash)) {
          continue;
        }

        if (!upload.needsUpload) {
          additions.add(
            UploadJob(
              upload: upload,
              status: UploadJobStatus.completed,
              sentBytes: upload.fileSize,
              mediaId: upload.existingMediaId,
              isDuplicate: true,
            ),
          );
          continue;
        }

        additions.add(
          UploadJob(
            upload: await storage.retainSource(upload),
            status: UploadJobStatus.pending,
          ),
        );
      }

      final latest = state.requireValue;
      final jobs = [...latest.jobs];
      final knownHashes = jobs.map((job) => job.id).toSet();
      jobs.addAll(additions.where((job) => knownHashes.add(job.id)));

      state = AsyncData(UploadQueueState(jobs: jobs, preparationError: null));
      await _saveJobs(_persistableJobs(jobs));
      unawaited(_drain());
    } catch (error) {
      if (ref.mounted) {
        state = AsyncData(
          state.requireValue.copyWith(
            isPreparing: false,
            preparationError: _messageOf(error),
          ),
        );
      }

      rethrow;
    }
  }

  Future<void> retry(String id) async {
    final current = state.value;

    if (current == null) {
      return;
    }

    final job = current.jobs.where((job) => job.id == id).firstOrNull;

    if (job == null || job.status != UploadJobStatus.failed) {
      return;
    }

    _replaceJob(
      job.copyWith(status: UploadJobStatus.pending, errorMessage: null),
    );
    await _persist();
    unawaited(_drain());
  }

  Future<void> remove(String id) async {
    final current = state.value;

    if (current == null) {
      return;
    }

    final job = current.jobs.where((job) => job.id == id).firstOrNull;

    if (job == null || job.status == UploadJobStatus.uploading) {
      return;
    }

    state = AsyncData(
      current.copyWith(
        jobs: current.jobs.where((candidate) => candidate.id != id).toList(),
      ),
    );
    await _persist();

    if (job.upload.needsUpload) {
      await (await ref.read(
        uploadQueueStorageProvider.future,
      )).removeSource(job.id);
    }
  }

  Future<void> _drain() async {
    if (_draining || state.value == null) {
      return;
    }

    _draining = true;

    try {
      while (ref.mounted) {
        final pending = state.requireValue.jobs
            .where((job) => job.status == UploadJobStatus.pending)
            .firstOrNull;

        if (pending == null) {
          return;
        }

        final uploading = pending.copyWith(
          status: UploadJobStatus.uploading,
          errorMessage: null,
        );
        _replaceJob(uploading);

        try {
          await _persist();
          final transfer = await ref.read(uploadTransferServiceProvider.future);
          var reportedBytes = uploading.sentBytes;
          final result = await transfer.transfer(
            uploading.upload,
            onProgress: (sent, total) {
              if (!ref.mounted ||
                  (sent != total &&
                      (sent - reportedBytes).abs() < _progressStep)) {
                return;
              }

              reportedBytes = sent;
              final currentJob = _job(uploading.id);

              if (currentJob?.status == UploadJobStatus.uploading) {
                _replaceJob(currentJob!.copyWith(sentBytes: sent));
              }
            },
          );

          if (!ref.mounted) {
            return;
          }

          _replaceJob(
            _job(uploading.id)!.copyWith(
              status: UploadJobStatus.completed,
              sentBytes: uploading.upload.fileSize,
              mediaId: result.mediaId,
              isDuplicate: result.isDuplicate,
              errorMessage: null,
            ),
          );
          await _persist();

          try {
            await (await ref.read(
              uploadQueueStorageProvider.future,
            )).removeSource(uploading.id);
          } on FileSystemException {
            // 큐에서는 완료 처리 유지. 남은 관리 파일은 같은 해시 재선택 시 재사용.
          }
        } catch (error) {
          if (!ref.mounted) {
            return;
          }

          final currentJob = _job(uploading.id);

          if (currentJob != null) {
            _replaceJob(
              currentJob.copyWith(
                status: UploadJobStatus.failed,
                errorMessage: _messageOf(error),
              ),
            );
            await _persist();
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  UploadJob? _job(String id) {
    return state.value?.jobs.where((job) => job.id == id).firstOrNull;
  }

  void _replaceJob(UploadJob replacement) {
    final current = state.requireValue;

    state = AsyncData(
      current.copyWith(
        jobs: current.jobs
            .map((job) => job.id == replacement.id ? replacement : job)
            .toList(growable: false),
      ),
    );
  }

  Future<void> _persist() async {
    await _saveJobs(_persistableJobs(state.requireValue.jobs));
  }

  Future<void> _saveJobs(List<UploadJob> jobs) {
    final previousWrite = _writeTail;
    final write = () async {
      try {
        await previousWrite;
      } catch (_) {
        // 앞선 저장 실패와 무관하게 최신 상태 저장 시도 유지.
      }

      final storage = await ref.read(uploadQueueStorageProvider.future);
      await storage.save(jobs);
    }();
    _writeTail = write;

    return write;
  }

  static List<UploadJob> _persistableJobs(List<UploadJob> jobs) {
    return jobs
        .where((job) => job.status != UploadJobStatus.completed)
        .toList(growable: false);
  }

  static String _messageOf(Object error) {
    return switch (error) {
      ApiException() => error.message,
      FileSystemException() => '선택한 파일을 읽거나 보관하지 못했습니다.',
      FormatException() => error.message,
      _ => '파일을 업로드하지 못했습니다.',
    };
  }
}

const Object _unset = Object();

final uploadControllerProvider =
    AsyncNotifierProvider<UploadController, UploadQueueState>(
      UploadController.new,
    );
