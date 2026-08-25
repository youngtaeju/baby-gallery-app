import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:family_gallery/features/gallery/media_list_controller.dart';
import 'package:family_gallery/features/gallery/media_models.dart';
import 'package:family_gallery/features/gallery/media_viewer_page.dart';
import 'package:family_gallery/features/gallery/original_image_loader.dart';
import 'package:family_gallery/features/gallery/thumbnail_loader.dart';
import 'package:family_gallery/features/gallery/video_streaming.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';

void main() {
  testWidgets('마지막 항목 근처에서 기존 목록에 다음 페이지를 추가한다', (tester) async {
    final controller = _AppendingMediaListController(
      MediaListState(items: [_item(3), _item(2)], nextCursor: 'next'),
    );

    await _pumpViewer(tester, controller, initialIndex: 1);
    await tester.pump();

    expect(controller.loadMoreCallCount, 1);
    expect(controller.state.requireValue.items.map((item) => item.id), [
      3,
      2,
      1,
    ]);
  });

  testWidgets('다음 페이지 조회 실패를 뷰어에서 다시 시도한다', (tester) async {
    final controller = _AppendingMediaListController(
      MediaListState(
        items: [_item(1)],
        nextCursor: 'next',
        loadMoreError: '목록을 더 불러오지 못했습니다.',
      ),
      appendOnLoad: false,
    );

    await _pumpViewer(tester, controller, initialIndex: 0);
    await tester.pump();

    expect(find.text('목록을 더 불러오지 못했습니다.'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pump();

    expect(controller.loadMoreCallCount, 2);
  });

  testWidgets('이미지를 원본 확대 뷰어로 표시한다', (tester) async {
    final controller = _AppendingMediaListController(
      MediaListState(items: [_item(1)], nextCursor: null),
    );
    final originalLoader = _MemoryOriginalImageLoader();

    await _pumpViewer(
      tester,
      controller,
      initialIndex: 0,
      originalLoader: originalLoader,
    );
    await tester.pump();

    final photoView = tester.widget<PhotoView>(find.byType(PhotoView));

    expect(photoView.imageProvider, originalLoader.imageProvider(1));
    expect(photoView.initialScale, PhotoViewComputedScale.contained);
    expect(photoView.minScale, PhotoViewComputedScale.contained);
    expect(photoView.maxScale, isNotNull);
  });

  testWidgets('미디어 화면을 탭하면 상단 컨트롤을 숨기고 다시 표시한다', (tester) async {
    final controller = _AppendingMediaListController(
      MediaListState(items: [_item(1)], nextCursor: null),
    );

    await _pumpViewer(
      tester,
      controller,
      initialIndex: 0,
      originalLoader: _MemoryOriginalImageLoader(),
    );
    await tester.pump();

    IgnorePointer topControls() =>
        tester.widget(find.byKey(const Key('viewer-top-controls')));

    expect(topControls().ignoring, isFalse);

    await tester.tap(find.byType(PhotoView));
    await tester.pump(const Duration(milliseconds: 300));

    expect(topControls().ignoring, isTrue);

    await tester.tap(find.byType(PhotoView));
    await tester.pump(const Duration(milliseconds: 300));

    expect(topControls().ignoring, isFalse);
  });

  testWidgets('아래로 스와이프하면 미디어 뷰어를 닫는다', (tester) async {
    final controller = _AppendingMediaListController(
      MediaListState(items: [_item(1)], nextCursor: null),
    );

    await _pumpViewerRoute(tester, controller, initialIndex: 0);

    expect(find.byKey(const Key('media-viewer-pages')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('media-viewer-pages')),
      const Offset(0, 240),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('media-viewer-pages')), findsNothing);
    expect(find.byKey(const Key('viewer-launcher')), findsOneWidget);
  });

  testWidgets('확대한 이미지를 아래로 이동할 때는 뷰어를 닫지 않는다', (tester) async {
    final controller = _AppendingMediaListController(
      MediaListState(items: [_item(1)], nextCursor: null),
    );

    await _pumpViewerRoute(
      tester,
      controller,
      initialIndex: 0,
      originalLoader: _MemoryOriginalImageLoader(),
    );
    await tester.pump();

    final photoView = tester.widget<PhotoView>(find.byType(PhotoView));
    photoView.scaleStateChangedCallback!(PhotoViewScaleState.zoomedIn);

    await tester.drag(find.byType(PhotoView), const Offset(0, 240));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('media-viewer-pages')), findsOneWidget);
  });

  testWidgets('영상 스트림을 초기화하고 기본 재생 컨트롤을 제공한다', (tester) async {
    final mediaController = _AppendingMediaListController(
      MediaListState(
        items: [_item(1, mediaType: MediaType.video)],
        nextCursor: null,
      ),
    );
    final sourceLoader = _FakeVideoStreamSourceLoader();
    final playbackController = _FakeVideoPlaybackController();

    await _pumpViewer(
      tester,
      mediaController,
      initialIndex: 0,
      videoSourceLoader: sourceLoader,
      playbackFactory: (source) => playbackController,
    );
    await tester.pump();
    await tester.pump();

    expect(sourceLoader.preparedIds, [1]);
    expect(playbackController.initializeCallCount, 1);
    expect(find.byKey(const Key('fake-video-view')), findsOneWidget);
    expect(find.text('0:00 / 1:05'), findsOneWidget);

    await tester.tap(find.byTooltip('재생'));
    await tester.pump();

    expect(playbackController.playCallCount, 1);
    expect(find.byTooltip('일시정지'), findsOneWidget);

    await tester.tap(find.byTooltip('음소거'));
    await tester.pump();

    expect(playbackController.volume, 0);
    expect(find.byTooltip('음소거 해제'), findsOneWidget);
  });

  testWidgets('영상 페이지를 벗어나면 재생 controller를 해제한다', (tester) async {
    final mediaController = _AppendingMediaListController(
      MediaListState(
        items: [
          _item(2, mediaType: MediaType.video),
          _item(1),
        ],
        nextCursor: null,
      ),
    );
    final playbackController = _FakeVideoPlaybackController();

    await _pumpViewer(
      tester,
      mediaController,
      initialIndex: 0,
      videoSourceLoader: _FakeVideoStreamSourceLoader(),
      playbackFactory: (source) => playbackController,
    );
    await tester.pump();
    await tester.pump();

    final pageView = tester.widget<PageView>(
      find.byKey(const Key('media-viewer-pages')),
    );

    pageView.controller!.jumpToPage(1);
    await tester.pump();
    await tester.pump();

    expect(find.text('1.jpg'), findsOneWidget);
    expect(
      (playbackController.pauseCallCount, playbackController.disposeCallCount),
      (1, 1),
    );
  });

  testWidgets('영상 재생 오류 후 인증 소스부터 다시 준비한다', (tester) async {
    final mediaController = _AppendingMediaListController(
      MediaListState(
        items: [_item(1, mediaType: MediaType.video)],
        nextCursor: null,
      ),
    );
    final sourceLoader = _FakeVideoStreamSourceLoader();
    final controllers = [
      _FakeVideoPlaybackController(),
      _FakeVideoPlaybackController(),
    ];
    var controllerIndex = 0;

    await _pumpViewer(
      tester,
      mediaController,
      initialIndex: 0,
      videoSourceLoader: sourceLoader,
      playbackFactory: (source) => controllers[controllerIndex++],
    );
    await tester.pump();
    await tester.pump();

    controllers.first.emitError('HTTP 401');
    await tester.pump();
    await tester.pump();

    expect(find.text('다시 시도'), findsOneWidget);
    expect(controllers.first.disposeCallCount, 1);

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.pump();

    expect(sourceLoader.preparedIds, [1, 1]);
    expect(controllers.last.initializeCallCount, 1);
  });
}

Future<void> _pumpViewer(
  WidgetTester tester,
  _AppendingMediaListController controller, {
  required int initialIndex,
  OriginalImageLoader? originalLoader,
  VideoStreamSourceLoader? videoSourceLoader,
  VideoPlaybackControllerFactory? playbackFactory,
}) async {
  final pendingLoader = Completer<ThumbnailLoader>();
  final pendingOriginalLoader = Completer<OriginalImageLoader>();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaListControllerProvider.overrideWith(() => controller),
        thumbnailLoaderProvider.overrideWith((ref) => pendingLoader.future),
        originalImageLoaderProvider.overrideWith(
          (ref) => originalLoader == null
              ? pendingOriginalLoader.future
              : Future.value(originalLoader),
        ),
        if (videoSourceLoader != null)
          videoStreamSourceLoaderProvider.overrideWithValue(videoSourceLoader),
        if (playbackFactory != null)
          videoPlaybackControllerFactoryProvider.overrideWithValue(
            playbackFactory,
          ),
      ],
      child: MaterialApp(home: MediaViewerPage(initialIndex: initialIndex)),
    ),
  );
  await tester.pump();
}

Future<void> _pumpViewerRoute(
  WidgetTester tester,
  _AppendingMediaListController controller, {
  required int initialIndex,
  OriginalImageLoader? originalLoader,
}) async {
  final pendingLoader = Completer<ThumbnailLoader>();
  final pendingOriginalLoader = Completer<OriginalImageLoader>();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaListControllerProvider.overrideWith(() => controller),
        thumbnailLoaderProvider.overrideWith((ref) => pendingLoader.future),
        originalImageLoaderProvider.overrideWith(
          (ref) => originalLoader == null
              ? pendingOriginalLoader.future
              : Future.value(originalLoader),
        ),
      ],
      child: MaterialApp(
        initialRoute: '/viewer',
        routes: {
          '/': (context) => const ColoredBox(
            key: Key('viewer-launcher'),
            color: Colors.black,
          ),
          '/viewer': (context) => MediaViewerPage(initialIndex: initialIndex),
        },
      ),
    ),
  );
  await tester.pump();
}

MediaItem _item(int id, {MediaType mediaType = MediaType.image}) {
  return MediaItem(
    id: id,
    mediaType: mediaType,
    fileName: mediaType == MediaType.video ? '$id.mp4' : '$id.jpg',
    fileSize: 100,
    capturedAt: DateTime.utc(2026, 8, 24),
    width: 100,
    height: 100,
    durationMs: null,
  );
}

class _FakeVideoStreamSourceLoader implements VideoStreamSourceLoader {
  final List<int> preparedIds = [];

  @override
  Future<VideoStreamSource> prepare(int mediaId) async {
    preparedIds.add(mediaId);

    return VideoStreamSource(
      uri: Uri.parse('https://example.test/media/$mediaId/original'),
      headers: const {'Authorization': 'Bearer token'},
    );
  }
}

class _FakeVideoPlaybackController implements VideoPlaybackController {
  VideoPlayerValue _value = const VideoPlayerValue(
    duration: Duration(seconds: 65),
    size: Size(640, 480),
  );

  int initializeCallCount = 0;
  int playCallCount = 0;
  int pauseCallCount = 0;
  int disposeCallCount = 0;
  final List<VoidCallback> _listeners = [];

  double get volume => _value.volume;

  @override
  VideoPlayerValue get value => _value;

  @override
  Widget buildView() =>
      const ColoredBox(key: Key('fake-video-view'), color: Colors.black);

  @override
  Future<void> initialize() async {
    initializeCallCount++;
    _update(_value.copyWith(isInitialized: true));
  }

  @override
  Future<void> play() async {
    playCallCount++;
    _update(_value.copyWith(isPlaying: true));
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    _update(_value.copyWith(isPlaying: false));
  }

  @override
  Future<void> seekTo(Duration position) async {
    _update(_value.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async {
    _update(_value.copyWith(volume: volume));
  }

  void emitError(String description) {
    _update(VideoPlayerValue.erroneous(description));
  }

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    _listeners.clear();
  }

  void _update(VideoPlayerValue value) {
    _value = value;

    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }
}

class _AppendingMediaListController extends MediaListController {
  _AppendingMediaListController(this._initial, {this.appendOnLoad = true});

  final MediaListState _initial;
  final bool appendOnLoad;

  int loadMoreCallCount = 0;

  @override
  Future<MediaListState> build() async => _initial;

  @override
  Future<void> loadMore() async {
    loadMoreCallCount++;

    if (!appendOnLoad) {
      return;
    }

    final current = state.requireValue;

    state = AsyncData(
      MediaListState(items: [...current.items, _item(1)], nextCursor: null),
    );
  }
}

class _MemoryOriginalImageLoader implements OriginalImageLoader {
  static final Uint8List _imageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  @override
  ImageProvider imageProvider(int mediaId) {
    return MemoryImage(_imageBytes);
  }

  @override
  Future<Uint8List> load(
    int mediaId, {
    ProgressCallback? onReceiveProgress,
  }) async {
    return _imageBytes;
  }
}
