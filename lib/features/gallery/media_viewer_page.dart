import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'media_list_controller.dart';
import 'media_models.dart';
import 'thumbnail_loader.dart';

class MediaViewerPage extends ConsumerStatefulWidget {
  const MediaViewerPage({required this.initialIndex, super.key});

  final int initialIndex;

  @override
  ConsumerState<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends ConsumerState<MediaViewerPage> {
  static const int _loadMoreThreshold = 5;

  late final PageController _pageController;
  late int _currentIndex;
  int? _lastLoadMoreItemCount;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _loadMoreIfNeeded() {
    if (!mounted) {
      return;
    }

    final state = ref.read(mediaListControllerProvider).value;

    if (state == null ||
        !state.hasMore ||
        _lastLoadMoreItemCount == state.items.length ||
        _currentIndex < state.items.length - _loadMoreThreshold) {
      return;
    }

    _lastLoadMoreItemCount = state.items.length;
    ref.read(mediaListControllerProvider.notifier).loadMore();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
    _loadMoreIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(mediaListControllerProvider);
    final state = media.value;
    final title = state != null && _currentIndex < state.items.length
        ? state.items[_currentIndex].fileName
        : '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: media.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _ViewerUnavailable(),
        data: (state) {
          if (state.items.isEmpty ||
              widget.initialIndex >= state.items.length) {
            return const _ViewerUnavailable();
          }

          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _loadMoreIfNeeded(),
          );

          return Stack(
            children: [
              PageView.builder(
                key: const Key('media-viewer-pages'),
                controller: _pageController,
                itemCount: state.items.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _ViewerPage(
                  key: ValueKey('viewer-media-${state.items[index].id}'),
                  item: state.items[index],
                ),
              ),
              if (state.isLoadingMore)
                const Positioned(
                  right: 16,
                  bottom: 16,
                  child: CircularProgressIndicator(),
                )
              else if (state.loadMoreError != null)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: _LoadMoreFailure(
                    message: state.loadMoreError!,
                    onRetry: () => ref
                        .read(mediaListControllerProvider.notifier)
                        .loadMore(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ViewerPage extends ConsumerWidget {
  const _ViewerPage({required this.item, super.key});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loader = ref.watch(thumbnailLoaderProvider);

    return Semantics(
      image: true,
      label: item.mediaType == MediaType.video
          ? '${item.fileName}, 동영상'
          : '${item.fileName}, 이미지',
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            loader.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => const _ViewerUnavailable(),
              data: (loader) => Image(
                image: loader.imageProvider(item.id),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    const _ViewerUnavailable(),
              ),
            ),
            if (item.mediaType == MediaType.video)
              const Center(
                child: Icon(
                  Icons.play_circle_outline,
                  color: Colors.white,
                  size: 72,
                ),
              ),
          ],
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
    return Material(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

class _ViewerUnavailable extends StatelessWidget {
  const _ViewerUnavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
    );
  }
}
