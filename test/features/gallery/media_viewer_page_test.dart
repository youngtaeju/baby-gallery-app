import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:family_gallery/features/gallery/media_list_controller.dart';
import 'package:family_gallery/features/gallery/media_models.dart';
import 'package:family_gallery/features/gallery/media_viewer_page.dart';
import 'package:family_gallery/features/gallery/original_image_loader.dart';
import 'package:family_gallery/features/gallery/thumbnail_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_view/photo_view.dart';

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
}

Future<void> _pumpViewer(
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
      child: MaterialApp(home: MediaViewerPage(initialIndex: initialIndex)),
    ),
  );
  await tester.pump();
}

MediaItem _item(int id) {
  return MediaItem(
    id: id,
    mediaType: MediaType.image,
    fileName: '$id.jpg',
    fileSize: 100,
    capturedAt: DateTime.utc(2026, 8, 24),
    width: 100,
    height: 100,
    durationMs: null,
  );
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
