import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'upload_controller.dart';
import 'upload_models.dart';

class UploadQueueSheet extends ConsumerWidget {
  const UploadQueueSheet({required this.onSelectFiles, super.key});

  final Future<void> Function() onSelectFiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploads = ref.watch(uploadControllerProvider);
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '업로드',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: '닫기',
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('select-upload-files'),
                onPressed: uploads.value?.isPreparing == true
                    ? null
                    : onSelectFiles,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  uploads.value?.isPreparing == true
                      ? '파일 준비 중'
                      : '사진 및 동영상 선택',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: uploads.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
                error: (error, stackTrace) => _QueueFailure(
                  onRetry: () => ref.invalidate(uploadControllerProvider),
                ),
                data: (state) {
                  if (state.jobs.isEmpty && state.preparationError == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        '대기 중인 파일이 없습니다.',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    );
                  }

                  return ListView(
                    shrinkWrap: true,
                    children: [
                      if (state.isPreparing)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator(),
                        ),
                      if (state.preparationError case final message?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            message,
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      for (final job in state.jobs)
                        _UploadJobTile(
                          job: job,
                          onRetry: () => ref
                              .read(uploadControllerProvider.notifier)
                              .retry(job.id),
                          onRemove: () => ref
                              .read(uploadControllerProvider.notifier)
                              .remove(job.id),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadJobTile extends StatelessWidget {
  const _UploadJobTile({
    required this.job,
    required this.onRetry,
    required this.onRemove,
  });

  final UploadJob job;

  final VoidCallback onRetry;

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = _statusOf(job);
    final progress = job.upload.fileSize == 0
        ? null
        : (job.sentBytes / job.upload.fileSize).clamp(0.0, 1.0);

    return ListTile(
      key: ValueKey('upload-job-${job.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(status.icon, color: status.color(colors)),
      title: Text(
        job.upload.source.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            job.errorMessage ?? status.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: job.status == UploadJobStatus.failed
                ? TextStyle(color: colors.error)
                : null,
          ),
          if (job.status == UploadJobStatus.uploading) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress),
          ],
        ],
      ),
      trailing: switch (job.status) {
        UploadJobStatus.failed => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              tooltip: '다시 시도',
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              tooltip: '목록에서 제거',
            ),
          ],
        ),
        UploadJobStatus.uploading => null,
        _ => IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close),
          tooltip: '목록에서 제거',
        ),
      },
    );
  }
}

class _UploadStatus {
  const _UploadStatus({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;

  final IconData icon;

  final Color Function(ColorScheme colors) color;
}

_UploadStatus _statusOf(UploadJob job) {
  return switch (job.status) {
    UploadJobStatus.pending => _UploadStatus(
      label: '업로드 대기 중',
      icon: Icons.schedule,
      color: (colors) => colors.onSurfaceVariant,
    ),
    UploadJobStatus.uploading => _UploadStatus(
      label: '${_percentage(job)}% 업로드 중',
      icon: Icons.cloud_upload_outlined,
      color: (colors) => colors.primary,
    ),
    UploadJobStatus.completed => _UploadStatus(
      label: job.isDuplicate ? '이미 등록된 파일' : '업로드 완료',
      icon: Icons.check_circle_outline,
      color: (colors) => colors.primary,
    ),
    UploadJobStatus.failed => _UploadStatus(
      label: '업로드 실패',
      icon: Icons.error_outline,
      color: (colors) => colors.error,
    ),
  };
}

int _percentage(UploadJob job) {
  if (job.upload.fileSize == 0) {
    return 0;
  }

  return ((job.sentBytes / job.upload.fileSize) * 100).clamp(0, 100).round();
}

class _QueueFailure extends StatelessWidget {
  const _QueueFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('업로드 대기열을 불러오지 못했습니다.'),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
