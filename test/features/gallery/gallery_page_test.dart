import 'dart:async';

import 'package:baby_gallery/features/auth/auth_controller.dart';
import 'package:baby_gallery/features/auth/auth_models.dart';
import 'package:baby_gallery/features/gallery/gallery_page.dart';
import 'package:baby_gallery/features/gallery/media_list_controller.dart';
import 'package:baby_gallery/features/gallery/media_models.dart';
import 'package:baby_gallery/features/gallery/thumbnail_loader.dart';
import 'package:baby_gallery/features/upload/upload_controller.dart';
import 'package:baby_gallery/features/upload/upload_file_picker.dart';
import 'package:baby_gallery/features/upload/upload_models.dart';
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

  testWidgets('viewer에게 업로드 진입점을 노출하지 않는다', (tester) async {
    await _pumpGallery(
      tester,
      _FixedMediaListController(MediaListState(items: [], nextCursor: null)),
    );

    expect(find.byKey(const Key('open-upload-queue')), findsNothing);
  });

  testWidgets('editor가 선택한 사진과 영상을 업로드 대기열에 추가한다', (tester) async {
    final uploadController = _FixedUploadController(UploadQueueState(jobs: []));
    final picker = _FakeUploadFilePicker([
      const LocalUploadFile(path: 'photo.jpg', fileName: '사진.jpg'),
      const LocalUploadFile(path: 'video.mp4', fileName: '영상.mp4'),
    ]);

    await _pumpGallery(
      tester,
      _FixedMediaListController(MediaListState(items: [], nextCursor: null)),
      role: UserRole.editor,
      uploadController: uploadController,
      uploadFilePicker: picker,
    );

    await tester.tap(find.byKey(const Key('open-upload-queue')));
    await tester.pumpAndSettle();
    expect(find.text('사진 및 동영상 선택'), findsOneWidget);

    await tester.tap(find.byKey(const Key('select-upload-files')));
    await tester.pump();

    expect(picker.callCount, 1);
    expect(uploadController.addedFiles.map((file) => file.fileName), [
      '사진.jpg',
      '영상.mp4',
    ]);
  });

  testWidgets('업로드 완료 시 갤러리 첫 페이지를 새로고침한다', (tester) async {
    final mediaController = _FixedMediaListController(
      MediaListState(items: [], nextCursor: null),
    );
    final uploadController = _FixedUploadController(UploadQueueState(jobs: []));

    await _pumpGallery(
      tester,
      mediaController,
      role: UserRole.editor,
      uploadController: uploadController,
      uploadFilePicker: _FakeUploadFilePicker(const []),
    );

    uploadController.completeUpload();
    await tester.pump();

    expect(mediaController.refreshCallCount, 1);
  });

  testWidgets('Android에서 복구한 선택 결과를 업로드 대기열에 추가한다', (tester) async {
    final uploadController = _FixedUploadController(UploadQueueState(jobs: []));
    final picker = _FakeUploadFilePicker(
      const [],
      lostFiles: const [
        LocalUploadFile(path: 'recovered.jpg', fileName: '복구 사진.jpg'),
      ],
    );

    await _pumpGallery(
      tester,
      _FixedMediaListController(MediaListState(items: [], nextCursor: null)),
      role: UserRole.editor,
      uploadController: uploadController,
      uploadFilePicker: picker,
    );
    await tester.pump();

    expect(picker.retrieveLostCallCount, 1);
    expect(uploadController.addedFiles.single.fileName, '복구 사진.jpg');
  });

  testWidgets('실패한 업로드를 대기열 시트에서 다시 시도한다', (tester) async {
    final failedJob = UploadJob(
      upload: const PreparedUpload(
        source: LocalUploadFile(path: 'video.mp4', fileName: '가족 영상.mp4'),
        fileSize: 10,
        contentHash:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        existingMediaId: null,
      ),
      status: UploadJobStatus.failed,
      sentBytes: 5,
      errorMessage: '서버에 연결할 수 없습니다.',
    );
    final uploadController = _FixedUploadController(
      UploadQueueState(jobs: [failedJob]),
    );

    await _pumpGallery(
      tester,
      _FixedMediaListController(MediaListState(items: [], nextCursor: null)),
      role: UserRole.editor,
      uploadController: uploadController,
      uploadFilePicker: _FakeUploadFilePicker(const []),
    );

    await tester.tap(find.byKey(const Key('open-upload-queue')));
    await tester.pumpAndSettle();

    expect(find.text('가족 영상.mp4'), findsOneWidget);
    expect(find.text('서버에 연결할 수 없습니다.'), findsOneWidget);
    await tester.tap(find.byTooltip('다시 시도'));
    await tester.pump();
    await tester.tap(find.byTooltip('목록에서 제거'));
    await tester.pump();

    expect(uploadController.retriedIds, [failedJob.id]);
    expect(uploadController.removedIds, [failedJob.id]);
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
  UserRole role = UserRole.viewer,
  _FixedUploadController? uploadController,
  UploadFilePicker? uploadFilePicker,
}) async {
  final pendingLoader = Completer<ThumbnailLoader>();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          () => _SignedInAuthController(role),
        ),
        mediaListControllerProvider.overrideWith(() => mediaController),
        thumbnailLoaderProvider.overrideWith((ref) => pendingLoader.future),
        if (uploadController != null)
          uploadControllerProvider.overrideWith(() => uploadController),
        if (uploadFilePicker != null)
          uploadFilePickerProvider.overrideWithValue(uploadFilePicker),
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
  _SignedInAuthController(this.role);

  final UserRole role;

  @override
  Future<AuthUser?> build() async {
    return AuthUser(id: 1, username: 'tester', displayName: '테스터', role: role);
  }
}

class _FixedMediaListController extends MediaListController {
  _FixedMediaListController(this._state);

  final MediaListState _state;

  int loadMoreCallCount = 0;
  int refreshCallCount = 0;

  @override
  Future<MediaListState> build() async => _state;

  @override
  Future<void> loadMore() async {
    loadMoreCallCount++;
  }

  @override
  Future<void> refresh() async {
    refreshCallCount++;
  }
}

class _FixedUploadController extends UploadController {
  _FixedUploadController(this._state);

  final UploadQueueState _state;
  final List<LocalUploadFile> addedFiles = [];
  final List<String> retriedIds = [];
  final List<String> removedIds = [];

  @override
  Future<UploadQueueState> build() async => _state;

  @override
  Future<void> addFiles(List<LocalUploadFile> sources) async {
    addedFiles.addAll(sources);
  }

  @override
  Future<void> retry(String id) async {
    retriedIds.add(id);
  }

  @override
  Future<void> remove(String id) async {
    removedIds.add(id);
  }

  void completeUpload() {
    state = AsyncData(
      UploadQueueState(
        jobs: [
          UploadJob(
            upload: const PreparedUpload(
              source: LocalUploadFile(path: 'photo.jpg', fileName: '사진.jpg'),
              fileSize: 1,
              contentHash:
                  'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              existingMediaId: null,
            ),
            status: UploadJobStatus.completed,
            sentBytes: 1,
            mediaId: 1,
          ),
        ],
      ),
    );
  }
}

class _FakeUploadFilePicker implements UploadFilePicker {
  _FakeUploadFilePicker(this.files, {this.lostFiles = const []});

  final List<LocalUploadFile> files;
  final List<LocalUploadFile> lostFiles;
  int callCount = 0;
  int retrieveLostCallCount = 0;

  @override
  Future<List<LocalUploadFile>> pickFiles() async {
    callCount++;
    return files;
  }

  @override
  Future<List<LocalUploadFile>> retrieveLostFiles() async {
    retrieveLostCallCount++;
    return lostFiles;
  }
}
