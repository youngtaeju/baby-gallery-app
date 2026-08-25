import 'dart:async';

import 'package:family_gallery/features/gallery/media_list_controller.dart';
import 'package:family_gallery/features/gallery/media_models.dart';
import 'package:family_gallery/features/gallery/media_viewer_page.dart';
import 'package:family_gallery/features/gallery/thumbnail_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

Future<void> _pumpViewer(
  WidgetTester tester,
  _AppendingMediaListController controller, {
  required int initialIndex,
}) async {
  final pendingLoader = Completer<ThumbnailLoader>();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaListControllerProvider.overrideWith(() => controller),
        thumbnailLoaderProvider.overrideWith((ref) => pendingLoader.future),
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
