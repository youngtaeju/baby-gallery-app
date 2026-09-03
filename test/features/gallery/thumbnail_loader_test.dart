import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:baby_gallery/features/gallery/thumbnail_loader.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기존 Dio 인터셉터를 거쳐 인증된 썸네일을 요청한다', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.headers['Authorization'] = 'Bearer token';
            handler.next(options);
          },
        ),
      )
      ..httpClientAdapter = _StubAdapter((request) {
        capturedRequest = request;

        return _thumbnailResponse(request);
      });
    final loader = attachThumbnailCache(dio: dio, store: MemCacheStore());

    final bytes = await loader.load(17);

    expect(bytes, _thumbnailBytes);
    expect(capturedRequest.path, '/media/17/thumbnail');
    expect(capturedRequest.headers['Authorization'], 'Bearer token');
    expect(capturedRequest.responseType, ResponseType.bytes);
  });

  test('서버 max-age 동안 썸네일 응답을 재요청하지 않는다', () async {
    var requestCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter((request) {
        requestCount++;

        return _thumbnailResponse(request);
      });
    final loader = attachThumbnailCache(dio: dio, store: MemCacheStore());

    await loader.load(17);
    await loader.load(17);

    expect(requestCount, 1);
  });

  test('썸네일 캐시 설정이 다른 GET 응답에는 적용되지 않는다', () async {
    var requestCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter((request) {
        requestCount++;

        return _jsonResponse(request);
      });

    attachThumbnailCache(dio: dio, store: MemCacheStore());

    await dio.get<Map<String, dynamic>>('/media');
    await dio.get<Map<String, dynamic>>('/media');

    expect(requestCount, 2);
  });

  test('같은 로더와 미디어 ID는 동일한 Flutter 이미지 캐시 키를 사용한다', () {
    final dio = Dio();
    final loader = attachThumbnailCache(dio: dio, store: MemCacheStore());
    final attachedAgain = attachThumbnailCache(
      dio: dio,
      store: MemCacheStore(),
    );
    final first = loader.imageProvider(17);
    final second = attachedAgain.imageProvider(17);
    final other = loader.imageProvider(18);

    expect(attachedAgain, same(loader));
    expect(first, isA<ImageProvider>());
    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first, isNot(other));
  });
}

const _thumbnailBytes = <int>[1, 2, 3, 4];

ResponseBody _thumbnailResponse(RequestOptions request) {
  return ResponseBody.fromBytes(
    _thumbnailBytes,
    200,
    headers: {
      Headers.contentTypeHeader: ['image/webp'],
      'cache-control': ['private, max-age=604800'],
      'date': [HttpDate.format(DateTime.now().toUtc())],
      'etag': ['"hash-v1"'],
    },
  );
}

ResponseBody _jsonResponse(RequestOptions request) {
  return ResponseBody.fromBytes(
    Uint8List.fromList(
      utf8.encode(jsonEncode({'items': <Object>[], 'nextCursor': null})),
    ),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      'cache-control': ['private, max-age=604800'],
    },
  );
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._handler);

  final ResponseBody Function(RequestOptions request) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
