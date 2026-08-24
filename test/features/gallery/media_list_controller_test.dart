import 'dart:async';

import 'package:dio/dio.dart';
import 'package:family_gallery/core/api_exception.dart';
import 'package:family_gallery/features/gallery/media_list_controller.dart';
import 'package:family_gallery/features/gallery/media_models.dart';
import 'package:family_gallery/features/gallery/media_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('초기 페이지를 조회하고 다음 페이지를 이어 붙인다', () async {
    final repository = _FakeMediaRepository((cursor, limit) async {
      expect(limit, 50);

      return cursor == null
          ? _page(ids: [3, 2], nextCursor: 'next')
          : _page(ids: [1], nextCursor: null);
    });
    final container = _container(repository);
    addTearDown(container.dispose);

    final initial = await container.read(mediaListControllerProvider.future);

    expect(initial.items.map((item) => item.id), [3, 2]);
    expect(initial.hasMore, isTrue);

    await container.read(mediaListControllerProvider.notifier).loadMore();

    final loaded = container.read(mediaListControllerProvider).requireValue;

    expect(loaded.items.map((item) => item.id), [3, 2, 1]);
    expect(loaded.hasMore, isFalse);
    expect(repository.cursors, [null, 'next']);
  });

  test('진행 중인 다음 페이지 요청을 중복 실행하지 않는다', () async {
    final nextPage = Completer<MediaPage>();
    final repository = _FakeMediaRepository((cursor, limit) {
      return cursor == null
          ? Future.value(_page(ids: [2], nextCursor: 'next'))
          : nextPage.future;
    });
    final container = _container(repository);
    addTearDown(container.dispose);
    await container.read(mediaListControllerProvider.future);

    final controller = container.read(mediaListControllerProvider.notifier);
    final firstRequest = controller.loadMore();
    final secondRequest = controller.loadMore();

    expect(
      container.read(mediaListControllerProvider).requireValue.isLoadingMore,
      isTrue,
    );
    expect(repository.cursors, [null, 'next']);

    nextPage.complete(_page(ids: [1], nextCursor: null));
    await Future.wait([firstRequest, secondRequest]);

    expect(repository.cursors, [null, 'next']);
  });

  test('다음 페이지 실패 시 기존 항목과 재시도 커서를 유지한다', () async {
    final repository = _FakeMediaRepository((cursor, limit) async {
      if (cursor == null) {
        return _page(ids: [2], nextCursor: 'next');
      }

      throw const ApiException('목록을 불러오지 못했습니다.');
    });
    final container = _container(repository);
    addTearDown(container.dispose);
    await container.read(mediaListControllerProvider.future);

    await container.read(mediaListControllerProvider.notifier).loadMore();

    final failed = container.read(mediaListControllerProvider).requireValue;

    expect(failed.items.map((item) => item.id), [2]);
    expect(failed.nextCursor, 'next');
    expect(failed.isLoadingMore, isFalse);
    expect(failed.loadMoreError, '목록을 불러오지 못했습니다.');
  });

  test('새로고침 성공 시 첫 페이지로 교체한다', () async {
    var requestCount = 0;
    final repository = _FakeMediaRepository((cursor, limit) async {
      requestCount++;

      return requestCount == 1
          ? _page(ids: [2], nextCursor: 'old-next')
          : _page(ids: [4, 3], nextCursor: 'new-next');
    });
    final container = _container(repository);
    addTearDown(container.dispose);
    await container.read(mediaListControllerProvider.future);

    await container.read(mediaListControllerProvider.notifier).refresh();

    final refreshed = container.read(mediaListControllerProvider).requireValue;

    expect(refreshed.items.map((item) => item.id), [4, 3]);
    expect(refreshed.nextCursor, 'new-next');
    expect(refreshed.isRefreshing, isFalse);
  });

  test('새로고침 실패 시 기존 목록을 유지하고 오류를 전달한다', () async {
    var requestCount = 0;
    final repository = _FakeMediaRepository((cursor, limit) async {
      requestCount++;

      if (requestCount == 1) {
        return _page(ids: [2], nextCursor: 'next');
      }

      throw const ApiException('새로고침에 실패했습니다.');
    });
    final container = _container(repository);
    addTearDown(container.dispose);
    await container.read(mediaListControllerProvider.future);

    await expectLater(
      container.read(mediaListControllerProvider.notifier).refresh(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          '새로고침에 실패했습니다.',
        ),
      ),
    );

    final restored = container.read(mediaListControllerProvider).requireValue;

    expect(restored.items.map((item) => item.id), [2]);
    expect(restored.nextCursor, 'next');
    expect(restored.isRefreshing, isFalse);
  });
}

ProviderContainer _container(MediaRepository repository) {
  return ProviderContainer(
    overrides: [mediaRepositoryProvider.overrideWithValue(repository)],
  );
}

MediaPage _page({required List<int> ids, required String? nextCursor}) {
  return MediaPage(
    items: ids
        .map(
          (id) => MediaItem(
            id: id,
            mediaType: MediaType.image,
            fileName: '$id.jpg',
            fileSize: id,
            capturedAt: DateTime.utc(2026, 8, 24),
            width: 100,
            height: 100,
            durationMs: null,
          ),
        )
        .toList(),
    nextCursor: nextCursor,
  );
}

class _FakeMediaRepository extends MediaRepository {
  _FakeMediaRepository(this._list) : super(Dio());

  final Future<MediaPage> Function(String? cursor, int? limit) _list;

  final List<String?> cursors = [];

  @override
  Future<MediaPage> list({String? cursor, int? limit}) {
    cursors.add(cursor);

    return _list(cursor, limit);
  }
}
