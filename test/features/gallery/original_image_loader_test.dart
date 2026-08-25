import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:family_gallery/features/gallery/original_image_loader.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('기존 Dio 인터셉터를 거쳐 인증된 원본 이미지를 요청한다', () async {
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

        return _originalResponse();
      });
    final loader = attachOriginalImageCache(dio: dio, store: MemCacheStore());

    final bytes = await loader.load(17);

    expect(bytes, _originalBytes);
    expect(capturedRequest.path, '/media/17/original');
    expect(capturedRequest.headers['Authorization'], 'Bearer token');
    expect(capturedRequest.responseType, ResponseType.bytes);
  });

  test('서버 max-age 동안 원본 이미지 응답을 재요청하지 않는다', () async {
    var requestCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter((request) {
        requestCount++;

        return _originalResponse();
      });
    final loader = attachOriginalImageCache(dio: dio, store: MemCacheStore());

    await loader.load(17);
    await loader.load(17);

    expect(requestCount, 1);
  });

  test('같은 로더와 미디어 ID는 동일한 Flutter 이미지 캐시 키를 사용한다', () {
    final dio = Dio();
    final loader = attachOriginalImageCache(dio: dio, store: MemCacheStore());
    final attachedAgain = attachOriginalImageCache(
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

const _originalBytes = <int>[1, 2, 3, 4];

ResponseBody _originalResponse() {
  return ResponseBody.fromBytes(
    _originalBytes,
    200,
    headers: {
      Headers.contentTypeHeader: ['image/jpeg'],
      'cache-control': ['private, max-age=604800'],
      'date': [HttpDate.format(DateTime.now().toUtc())],
      'etag': ['"hash-v1"'],
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
