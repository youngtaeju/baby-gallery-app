import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import 'thumbnail_loader.dart';

final _loadersByDio = Expando<OriginalImageLoader>();

abstract interface class OriginalImageLoader {
  ImageProvider imageProvider(int mediaId);

  Future<Uint8List> load(int mediaId, {ProgressCallback? onReceiveProgress});
}

class DioOriginalImageLoader implements OriginalImageLoader {
  DioOriginalImageLoader._(this._dio, this._cacheOptions);

  final Dio _dio;
  final CacheOptions _cacheOptions;

  @override
  ImageProvider imageProvider(int mediaId) {
    return DioOriginalImageProvider(loader: this, mediaId: mediaId);
  }

  @override
  Future<Uint8List> load(
    int mediaId, {
    ProgressCallback? onReceiveProgress,
  }) async {
    final response = await _dio.get<List<int>>(
      '/media/$mediaId/original',
      options: _cacheOptions.toOptions().copyWith(
        responseType: ResponseType.bytes,
      ),
      onReceiveProgress: onReceiveProgress,
    );
    final bytes = response.data;

    if (bytes == null || bytes.isEmpty) {
      throw StateError('원본 이미지 응답이 비어 있습니다.');
    }

    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }
}

OriginalImageLoader attachOriginalImageCache({
  required Dio dio,
  required CacheStore store,
}) {
  final attached = _loadersByDio[dio];

  if (attached != null) {
    return attached;
  }

  // 동일 Dio에 캐시 인터셉터를 한 번만 부착하고 원본 요청에서만 캐시 사용.
  attachThumbnailCache(dio: dio, store: store);

  final loader = DioOriginalImageLoader._(
    dio,
    CacheOptions(store: store, policy: CachePolicy.request),
  );

  _loadersByDio[dio] = loader;

  return loader;
}

@immutable
class DioOriginalImageProvider extends ImageProvider<DioOriginalImageProvider> {
  const DioOriginalImageProvider({
    required this.loader,
    required this.mediaId,
    this.scale = 1,
  });

  final OriginalImageLoader loader;
  final int mediaId;
  final double scale;

  @override
  Future<DioOriginalImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(
    DioOriginalImageProvider key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();

    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode, chunkEvents),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: 'media/${key.mediaId}/original',
    );
  }

  Future<ui.Codec> _loadAsync(
    DioOriginalImageProvider key,
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
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
      rethrow;
    } finally {
      await chunkEvents.close();
    }
  }

  @override
  bool operator ==(Object other) {
    return other is DioOriginalImageProvider &&
        identical(other.loader, loader) &&
        other.mediaId == mediaId &&
        other.scale == scale;
  }

  @override
  int get hashCode => Object.hash(identityHashCode(loader), mediaId, scale);
}

final originalImageLoaderProvider = FutureProvider<OriginalImageLoader>((
  ref,
) async {
  final dio = ref.watch(dioProvider);
  final store = await ref.watch(thumbnailCacheStoreProvider.future);

  return attachOriginalImageCache(dio: dio, store: store);
});
