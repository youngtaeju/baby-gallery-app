import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api_client.dart';

final _loadersByDio = Expando<ThumbnailLoader>();

class ThumbnailLoader {
  ThumbnailLoader._(this._dio, this._cacheOptions);

  final Dio _dio;

  final CacheOptions _cacheOptions;

  ImageProvider imageProvider(int mediaId) {
    return DioThumbnailImageProvider(loader: this, mediaId: mediaId);
  }

  Future<Uint8List> load(
    int mediaId, {
    ProgressCallback? onReceiveProgress,
  }) async {
    final options = _cacheOptions.toOptions().copyWith(
      responseType: ResponseType.bytes,
    );
    final response = await _dio.get<List<int>>(
      '/media/$mediaId/thumbnail',
      options: options,
      onReceiveProgress: onReceiveProgress,
    );
    final bytes = response.data;

    if (bytes == null || bytes.isEmpty) {
      throw StateError('썸네일 응답이 비어 있습니다.');
    }

    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }
}

ThumbnailLoader attachThumbnailCache({
  required Dio dio,
  required CacheStore store,
}) {
  final attached = _loadersByDio[dio];

  if (attached != null) {
    return attached;
  }

  // 기본 캐시 비활성화. 썸네일 요청만 CachePolicy.request로 재정의.
  final defaultOptions = CacheOptions(
    store: store,
    policy: CachePolicy.noCache,
  );

  dio.interceptors.add(DioCacheInterceptor(options: defaultOptions));

  final loader = ThumbnailLoader._(
    dio,
    defaultOptions.copyWith(policy: CachePolicy.request),
  );

  _loadersByDio[dio] = loader;

  return loader;
}

@immutable
class DioThumbnailImageProvider
    extends ImageProvider<DioThumbnailImageProvider> {
  const DioThumbnailImageProvider({
    required this.loader,
    required this.mediaId,
    this.scale = 1,
  });

  final ThumbnailLoader loader;

  final int mediaId;

  final double scale;

  @override
  Future<DioThumbnailImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    DioThumbnailImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: 'media/${key.mediaId}/thumbnail',
    );
  }

  Future<ui.Codec> _loadAsync(
    DioThumbnailImageProvider key,
    ImageDecoderCallback decode,
    StreamController<ImageChunkEvent> chunkEvents,
  ) async {
    try {
      final bytes = await loader.load(
        mediaId,
        onReceiveProgress: (received, total) {
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: received,
              expectedTotalBytes: total > 0 ? total : null,
            ),
          );
        },
      );

      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      // 실패 키의 Flutter 메모리 캐시 잔류 방지.
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    } finally {
      await chunkEvents.close();
    }
  }

  @override
  bool operator ==(Object other) {
    return other is DioThumbnailImageProvider &&
        identical(other.loader, loader) &&
        other.mediaId == mediaId &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(loader), mediaId, scale);
}

final thumbnailCacheStoreProvider = FutureProvider<CacheStore>((ref) async {
  final cacheDirectory = await getApplicationCacheDirectory();
  final store = FileCacheStore(
    '${cacheDirectory.path}${Platform.pathSeparator}media-http',
  );

  ref.onDispose(() => unawaited(store.close()));

  return store;
});

final thumbnailLoaderProvider = FutureProvider<ThumbnailLoader>((ref) async {
  final dio = ref.watch(dioProvider);
  final store = await ref.watch(thumbnailCacheStoreProvider.future);

  return attachThumbnailCache(dio: dio, store: store);
});
