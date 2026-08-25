import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../auth/auth_controller.dart';
import 'media_list_controller.dart';
import 'media_models.dart';
import 'media_viewer_page.dart';
import 'thumbnail_loader.dart';

class GalleryPage extends ConsumerStatefulWidget {
  const GalleryPage({super.key});

  @override
  ConsumerState<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends ConsumerState<GalleryPage> {
  static const double _loadMoreThreshold = 600;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreIfNeeded);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreIfNeeded)
      ..dispose();
    super.dispose();
  }

  void _loadMoreIfNeeded() {
    if (_scrollController.position.extentAfter > _loadMoreThreshold) {
      return;
    }

    ref.read(mediaListControllerProvider.notifier).loadMore();
  }

  Future<void> _refresh() async {
    try {
      await ref.read(mediaListControllerProvider.notifier).refresh();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageOf(error))));
    }
  }

  void _openViewer(MediaItem item) {
    final items = ref.read(mediaListControllerProvider).value?.items;
    final initialIndex =
        items?.indexWhere((candidate) => candidate.id == item.id) ?? -1;

    if (initialIndex < 0) {
      return;
    }

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => MediaViewerPage(initialIndex: initialIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(mediaListControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('가족 갤러리'),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
          ),
        ],
      ),
      body: media.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _InitialFailure(
          message: _messageOf(error),
          onRetry: () => ref.invalidate(mediaListControllerProvider),
        ),
        data: (state) => RefreshIndicator(
          onRefresh: _refresh,
          child: _MediaScrollView(
            controller: _scrollController,
            state: state,
            onOpenMedia: _openViewer,
            onLoadMore: () =>
                ref.read(mediaListControllerProvider.notifier).loadMore(),
          ),
        ),
      ),
    );
  }
}

class _MediaScrollView extends StatelessWidget {
  const _MediaScrollView({
    required this.controller,
    required this.state,
    required this.onOpenMedia,
    required this.onLoadMore,
  });

  final ScrollController controller;

  final MediaListState state;

  final ValueChanged<MediaItem> onOpenMedia;

  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDate(state.items);

    return CustomScrollView(
      key: const Key('gallery-scroll'),
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (groups.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyGallery(),
          )
        else
          for (final group in groups) ...[
            SliverToBoxAdapter(child: _DateHeader(date: group.date)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 160,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: group.items.length,
                itemBuilder: (context, index) {
                  final item = group.items[index];

                  return _MediaTile(item: item, onTap: () => onOpenMedia(item));
                },
              ),
            ),
          ],
        if (state.isLoadingMore)
          const SliverToBoxAdapter(child: _LoadingMoreIndicator())
        else if (state.loadMoreError != null)
          SliverToBoxAdapter(
            child: _LoadMoreFailure(
              message: state.loadMoreError!,
              onRetry: onLoadMore,
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Text(
          '${date.year}년 ${date.month}월 ${date.day}일',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _MediaTile extends ConsumerWidget {
  const _MediaTile({required this.item, required this.onTap});

  final MediaItem item;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loader = ref.watch(thumbnailLoaderProvider);
    final label = item.mediaType == MediaType.video
        ? '${item.fileName}, 동영상${_durationLabel(item.durationMs)}'
        : '${item.fileName}, 이미지';

    return Semantics(
      button: true,
      image: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: ValueKey('media-tile-${item.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: loader.when(
                  loading: () => const _ThumbnailPlaceholder(),
                  error: (error, stackTrace) => const _ThumbnailUnavailable(),
                  data: (loader) => Image(
                    image: loader.imageProvider(item.id),
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) =>
                        const _ThumbnailUnavailable(),
                  ),
                ),
              ),
              if (item.mediaType == MediaType.video)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: _VideoBadge(durationMs: item.durationMs),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoBadge extends StatelessWidget {
  const _VideoBadge({required this.durationMs});

  final int? durationMs;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 15),
            if (durationMs != null) ...[
              const SizedBox(width: 2),
              Text(
                _formatDuration(durationMs!),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.photo_outlined,
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
      ),
    );
  }
}

class _ThumbnailUnavailable extends StatelessWidget {
  const _ThumbnailUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 48,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '아직 미디어가 없습니다.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _InitialFailure extends StatelessWidget {
  const _InitialFailure({required this.message, required this.onRetry});

  final String message;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

class _LoadingMoreIndicator extends StatelessWidget {
  const _LoadingMoreIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _LoadMoreFailure extends StatelessWidget {
  const _LoadMoreFailure({required this.message, required this.onRetry});

  final String message;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}

class _DateGroup {
  const _DateGroup({required this.date, required this.items});

  final DateTime date;

  final List<MediaItem> items;
}

List<_DateGroup> _groupByDate(List<MediaItem> items) {
  final groups = <_DateGroup>[];

  for (final item in items) {
    final capturedAt = item.capturedAt.toLocal();
    final date = DateTime(capturedAt.year, capturedAt.month, capturedAt.day);

    if (groups.isEmpty || groups.last.date != date) {
      groups.add(_DateGroup(date: date, items: [item]));
    } else {
      groups.last.items.add(item);
    }
  }

  return groups;
}

String _durationLabel(int? durationMs) {
  return durationMs == null ? '' : ', ${_formatDuration(durationMs)}';
}

String _formatDuration(int durationMs) {
  final duration = Duration(milliseconds: durationMs);
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _messageOf(Object error) {
  return error is ApiException ? error.message : '미디어를 불러오지 못했습니다.';
}
