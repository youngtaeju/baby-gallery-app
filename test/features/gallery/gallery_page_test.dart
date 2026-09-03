import 'dart:async';

import 'package:baby_gallery/features/auth/auth_controller.dart';
import 'package:baby_gallery/features/auth/auth_models.dart';
import 'package:baby_gallery/features/gallery/gallery_page.dart';
import 'package:baby_gallery/features/gallery/media_list_controller.dart';
import 'package:baby_gallery/features/gallery/media_models.dart';
import 'package:baby_gallery/features/gallery/thumbnail_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('촬영일별 그리드와 영상 길이를 표시한다', (tester) async {
    final state = MediaListState(
      items: [
        _item(id: 2, capturedAt: DateTime(2026, 8, 24)),
        _item(
          id: 1,
          capturedAt: DateTime(2026, 8, 23),
          mediaType: MediaType.video,
          durationMs: 65000,
        ),
      ],
      nextCursor: null,
    );

    await _pumpGallery(tester, _FixedMediaListController(state));

    expect(find.text('2026년 8월 24일'), findsOneWidget);
    expect(find.text('2026년 8월 23일'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('다음 페이지 실패 안내에서 다시 시도한다', (tester) async {
    final controller = _FixedMediaListController(
      MediaListState(
        items: [_item(id: 1, capturedAt: DateTime(2026, 8, 24))],
        nextCursor: 'next',
        loadMoreError: '목록을 더 불러오지 못했습니다.',
      ),
    );

    await _pumpGallery(tester, controller);

    expect(find.text('목록을 더 불러오지 못했습니다.'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pump();

    expect(controller.loadMoreCallCount, 1);
  });

  testWidgets('좁은 다크 화면에서도 그리드가 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final state = MediaListState(
      items: [
        _item(
          id: 1,
          capturedAt: DateTime(2026, 8, 24),
          mediaType: MediaType.video,
          durationMs: 3723000,
        ),
      ],
      nextCursor: null,
    );

    await _pumpGallery(
      tester,
      _FixedMediaListController(state),
      theme: ThemeData.dark(),
    );

    expect(find.text('1:02:03'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('선택한 미디어부터 뷰어를 열고 좌우로 이동한다', (tester) async {
    final state = MediaListState(
      items: [
        _item(id: 3, capturedAt: DateTime(2026, 8, 24)),
        _item(id: 2, capturedAt: DateTime(2026, 8, 24)),
        _item(id: 1, capturedAt: DateTime(2026, 8, 24)),
      ],
      nextCursor: null,
    );

    await _pumpGallery(tester, _FixedMediaListController(state));

    await tester.tap(find.byKey(const ValueKey('media-tile-2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('media-viewer-pages')), findsOneWidget);
    expect(find.text('2.jpg'), findsOneWidget);

    await tester.fling(
      find.byKey(const Key('media-viewer-pages')),
      const Offset(-500, 0),
      1000,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1.jpg'), findsOneWidget);
  });

  testWidgets('뷰어에서 돌아오면 갤러리 스크롤 위치를 유지한다', (tester) async {
    final state = MediaListState(
      items: [
        for (var id = 30; id >= 1; id--)
          _item(id: id, capturedAt: DateTime(2026, 8, 24)),
      ],
      nextCursor: null,
    );

    await _pumpGallery(tester, _FixedMediaListController(state));
    final target = find.byKey(const ValueKey('media-tile-10'));
    final scrollableFinder = find.descendant(
      of: find.byKey(const Key('gallery-scroll')),
      matching: find.byType(Scrollable),
    );

    await tester.scrollUntilVisible(target, 300, scrollable: scrollableFinder);
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(scrollableFinder);
    final offsetBeforeOpen = scrollable.position.pixels;

    await tester.tap(target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(scrollable.position.pixels, offsetBeforeOpen);
    expect(find.byKey(const ValueKey('media-tile-10')), findsOneWidget);
  });
}

Future<void> _pumpGallery(
  WidgetTester tester,
  _FixedMediaListController mediaController, {
  ThemeData? theme,
}) async {
  final pendingLoader = Completer<ThumbnailLoader>();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_SignedInAuthController.new),
        mediaListControllerProvider.overrideWith(() => mediaController),
        thumbnailLoaderProvider.overrideWith((ref) => pendingLoader.future),
      ],
      child: MaterialApp(theme: theme, home: const GalleryPage()),
    ),
  );
  await tester.pump();
}

MediaItem _item({
  required int id,
  required DateTime capturedAt,
  MediaType mediaType = MediaType.image,
  int? durationMs,
}) {
  return MediaItem(
    id: id,
    mediaType: mediaType,
    fileName: '$id.jpg',
    fileSize: 100,
    capturedAt: capturedAt,
    width: 100,
    height: 100,
    durationMs: durationMs,
  );
}

class _SignedInAuthController extends AuthController {
  @override
  Future<AuthUser?> build() async {
    return const AuthUser(
      id: 1,
      username: 'tester',
      displayName: '테스터',
      role: UserRole.viewer,
    );
  }
}

class _FixedMediaListController extends MediaListController {
  _FixedMediaListController(this._state);

  final MediaListState _state;

  int loadMoreCallCount = 0;

  @override
  Future<MediaListState> build() async => _state;

  @override
  Future<void> loadMore() async {
    loadMoreCallCount++;
  }
}
