import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import 'media_models.dart';
import 'media_repository.dart';

class MediaListState {
  MediaListState({
    required List<MediaItem> items,
    required this.nextCursor,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.loadMoreError,
  }) : items = List.unmodifiable(items);

  final List<MediaItem> items;

  final String? nextCursor;

  final bool isRefreshing;

  final bool isLoadingMore;

  final String? loadMoreError;

  bool get hasMore => nextCursor != null;
}

class MediaListController extends AsyncNotifier<MediaListState> {
  static const int _pageSize = 50;

  int _requestVersion = 0;

  @override
  Future<MediaListState> build() async {
    _requestVersion++;

    final page = await ref.read(mediaRepositoryProvider).list(limit: _pageSize);

    return _stateFrom(page);
  }

  Future<void> refresh() async {
    final current = state.value;

    if (current == null || current.isRefreshing) {
      return;
    }

    final requestVersion = ++_requestVersion;

    state = AsyncData(
      MediaListState(
        items: current.items,
        nextCursor: current.nextCursor,
        isRefreshing: true,
        loadMoreError: current.loadMoreError,
      ),
    );

    try {
      final page = await ref
          .read(mediaRepositoryProvider)
          .list(limit: _pageSize);

      if (!ref.mounted || requestVersion != _requestVersion) {
        return;
      }

      state = AsyncData(_stateFrom(page));
    } catch (_) {
      if (ref.mounted && requestVersion == _requestVersion) {
        state = AsyncData(
          MediaListState(
            items: current.items,
            nextCursor: current.nextCursor,
            loadMoreError: current.loadMoreError,
          ),
        );
      }

      rethrow;
    }
  }

  Future<void> loadMore() async {
    final current = state.value;

    if (current == null ||
        current.isRefreshing ||
        current.isLoadingMore ||
        !current.hasMore) {
      return;
    }

    final requestVersion = _requestVersion;

    state = AsyncData(
      MediaListState(
        items: current.items,
        nextCursor: current.nextCursor,
        isLoadingMore: true,
      ),
    );

    try {
      final page = await ref
          .read(mediaRepositoryProvider)
          .list(cursor: current.nextCursor, limit: _pageSize);

      if (!ref.mounted || requestVersion != _requestVersion) {
        return;
      }

      state = AsyncData(
        MediaListState(
          items: [...current.items, ...page.items],
          nextCursor: page.nextCursor,
        ),
      );
    } catch (error) {
      if (!ref.mounted || requestVersion != _requestVersion) {
        return;
      }

      state = AsyncData(
        MediaListState(
          items: current.items,
          nextCursor: current.nextCursor,
          loadMoreError: _messageOf(error),
        ),
      );
    }
  }

  static MediaListState _stateFrom(MediaPage page) {
    return MediaListState(items: page.items, nextCursor: page.nextCursor);
  }

  static String _messageOf(Object error) {
    return error is ApiException ? error.message : '미디어를 더 불러오지 못했습니다.';
  }
}

final mediaListControllerProvider =
    AsyncNotifierProvider<MediaListController, MediaListState>(
      MediaListController.new,
    );
