import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

import 'media_list_controller.dart';
import 'media_models.dart';
import 'original_image_loader.dart';
import 'thumbnail_loader.dart';
import 'video_streaming.dart';

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
              PhotoViewGestureDetectorScope(
                axis: Axis.horizontal,
                child: PageView.builder(
                  key: const Key('media-viewer-pages'),
                  controller: _pageController,
                  itemCount: state.items.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) => _ViewerPage(
                    key: ValueKey('viewer-media-${state.items[index].id}'),
                    item: state.items[index],
                    isActive: index == _currentIndex,
                  ),
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
  const _ViewerPage({required this.item, required this.isActive, super.key});

  final MediaItem item;
  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (item.mediaType == MediaType.image) {
      return _ImageViewerPage(item: item);
    }

    return _VideoViewerPage(item: item, isActive: isActive);
  }
}

class _VideoViewerPage extends ConsumerStatefulWidget {
  const _VideoViewerPage({required this.item, required this.isActive});

  final MediaItem item;
  final bool isActive;

  @override
  ConsumerState<_VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends ConsumerState<_VideoViewerPage>
    with WidgetsBindingObserver {
  VideoPlaybackController? _controller;
  Object? _error;
  bool _isInitializing = false;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.isActive) {
      unawaited(_initialize());
    }
  }

  @override
  void didUpdateWidget(_VideoViewerPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isActive == oldWidget.isActive) {
      return;
    }

    if (widget.isActive) {
      unawaited(_initialize());
    } else {
      unawaited(_releaseController());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_controller?.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestVersion++;

    final controller = _controller;
    _controller = null;
    controller?.removeListener(_controllerChanged);

    if (controller != null) {
      unawaited(_pauseAndDispose(controller));
    }

    super.dispose();
  }

  Future<void> _initialize() async {
    if (_isInitializing || _controller != null || !widget.isActive) {
      return;
    }

    final requestVersion = ++_requestVersion;

    setState(() {
      _isInitializing = true;
      _error = null;
    });

    VideoPlaybackController? controller;

    try {
      final source = await ref
          .read(videoStreamSourceLoaderProvider)
          .prepare(widget.item.id);

      if (!mounted || !widget.isActive || requestVersion != _requestVersion) {
        return;
      }

      controller = ref.read(videoPlaybackControllerFactoryProvider)(source);
      _controller = controller;
      controller.addListener(_controllerChanged);

      await controller.initialize();

      if (!mounted || !widget.isActive || requestVersion != _requestVersion) {
        return;
      }

      setState(() => _isInitializing = false);
    } catch (error) {
      if (controller != null) {
        controller.removeListener(_controllerChanged);
        await controller.dispose();

        if (identical(_controller, controller)) {
          _controller = null;
        }
      }

      if (mounted && widget.isActive && requestVersion == _requestVersion) {
        setState(() {
          _isInitializing = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _releaseController() async {
    _requestVersion++;
    final controller = _controller;
    _controller = null;
    _isInitializing = false;
    _error = null;

    if (controller == null) {
      return;
    }

    controller.removeListener(_controllerChanged);
    await _pauseAndDispose(controller);
  }

  void _controllerChanged() {
    final controller = _controller;

    if (controller != null && controller.value.hasError) {
      final description = controller.value.errorDescription;

      _requestVersion++;
      _controller = null;
      _isInitializing = false;
      controller.removeListener(_controllerChanged);
      unawaited(_pauseAndDispose(controller));

      if (mounted) {
        setState(() {
          _error = StateError(description ?? '영상을 재생할 수 없습니다.');
        });
      }

      return;
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Semantics(
      label: '${widget.item.fileName}, 동영상',
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _VideoThumbnail(item: widget.item),
            if (_error != null)
              _ViewerLoadFailure(onRetry: _initialize)
            else if (controller == null ||
                _isInitializing ||
                !controller.value.isInitialized)
              const Center(child: CircularProgressIndicator())
            else ...[
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: controller.buildView(),
                ),
              ),
              _VideoControls(controller: controller),
              if (controller.value.isBuffering)
                const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _pauseAndDispose(VideoPlaybackController controller) async {
  try {
    await controller.pause();
  } catch (_) {
    // 오류 상태에서도 controller 해제 계속 진행.
  }

  try {
    await controller.dispose();
  } catch (_) {
    // 화면 이탈 정리 실패의 UI 오류 재노출 방지.
  }
}

class _VideoThumbnail extends ConsumerWidget {
  const _VideoThumbnail({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loader = ref.watch(thumbnailLoaderProvider);

    return loader.when(
      loading: () => const SizedBox.shrink(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (loader) => Image(
        image: loader.imageProvider(item.id),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  const _VideoControls({required this.controller});

  final VideoPlaybackController controller;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final durationMs = value.duration.inMilliseconds;
    final positionMs = value.position.inMilliseconds.clamp(0, durationMs);

    return Align(
      alignment: Alignment.bottomCenter,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.7),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _togglePlayback(value),
                  color: Colors.white,
                  tooltip: value.isPlaying ? '일시정지' : '재생',
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                Expanded(
                  child: Slider(
                    value: positionMs.toDouble(),
                    max: durationMs <= 0 ? 1 : durationMs.toDouble(),
                    onChanged: durationMs <= 0
                        ? null
                        : (position) => controller.seekTo(
                            Duration(milliseconds: position.round()),
                          ),
                  ),
                ),
                Text(
                  '${_formatViewerDuration(value.position)} / '
                  '${_formatViewerDuration(value.duration)}',
                  style: const TextStyle(color: Colors.white),
                ),
                IconButton(
                  onPressed: () =>
                      controller.setVolume(value.volume == 0 ? 1 : 0),
                  color: Colors.white,
                  tooltip: value.volume == 0 ? '음소거 해제' : '음소거',
                  icon: Icon(
                    value.volume == 0 ? Icons.volume_off : Icons.volume_up,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _togglePlayback(VideoPlayerValue value) async {
    if (value.isPlaying) {
      await controller.pause();
      return;
    }

    if (value.isCompleted) {
      await controller.seekTo(Duration.zero);
    }

    await controller.play();
  }
}

String _formatViewerDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _ImageViewerPage extends ConsumerStatefulWidget {
  const _ImageViewerPage({required this.item});

  final MediaItem item;

  @override
  ConsumerState<_ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends ConsumerState<_ImageViewerPage> {
  int _reloadVersion = 0;

  @override
  Widget build(BuildContext context) {
    final loader = ref.watch(originalImageLoaderProvider);

    return loader.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _ViewerLoadFailure(onRetry: _retryLoader),
      data: (loader) {
        final provider = loader.imageProvider(widget.item.id);

        return PhotoView(
          key: ValueKey('original-${widget.item.id}-$_reloadVersion'),
          imageProvider: provider,
          semanticLabel: '${widget.item.fileName}, 이미지',
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          filterQuality: FilterQuality.high,
          loadingBuilder: (context, progress) {
            final total = progress?.expectedTotalBytes;
            final value = total == null || total <= 0
                ? null
                : progress!.cumulativeBytesLoaded / total;

            return Center(child: CircularProgressIndicator(value: value));
          },
          errorBuilder: (context, error, stackTrace) => _ViewerLoadFailure(
            onRetry: () {
              PaintingBinding.instance.imageCache.evict(provider);
              setState(() => _reloadVersion++);
            },
          ),
        );
      },
    );
  }

  void _retryLoader() {
    ref.invalidate(originalImageLoaderProvider);
  }
}

class _ViewerLoadFailure extends StatelessWidget {
  const _ViewerLoadFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Colors.white70,
            size: 48,
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
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
