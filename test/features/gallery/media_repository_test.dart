import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:family_gallery/core/api_exception.dart';
import 'package:family_gallery/features/gallery/media_models.dart';
import 'package:family_gallery/features/gallery/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cursor와 limit을 전달해 다음 목록 페이지를 조회한다', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter((request) {
        capturedRequest = request;

        return _jsonResponse(request, 200, {
          'items': [
            {
              'id': 1,
              'mediaType': 'Image',
              'fileName': 'photo.jpg',
              'fileSize': 10,
              'capturedAt': '2026-08-24T00:00:00Z',
              'width': 100,
              'height': 80,
              'durationMs': null,
            },
          ],
          'nextCursor': null,
        });
      });

    final page = await MediaRepository(
      dio,
    ).list(cursor: 'opaque-cursor', limit: 25);

    expect(capturedRequest.path, '/media');
    expect(capturedRequest.queryParameters, {
      'cursor': 'opaque-cursor',
      'limit': 25,
    });
    expect(page.items.single.mediaType, MediaType.image);
  });

  test('선택하지 않은 쿼리 파라미터는 전송하지 않는다', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter((request) {
        capturedRequest = request;

        return _jsonResponse(request, 200, {
          'items': <Object>[],
          'nextCursor': null,
        });
      });

    await MediaRepository(dio).list();

    expect(capturedRequest.queryParameters, isEmpty);
  });

  test('API 실패를 앱 공용 예외로 변환한다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter(
        (request) =>
            _jsonResponse(request, 400, {'detail': 'cursor 값이 올바르지 않습니다.'}),
      );

    expect(
      () => MediaRepository(dio).list(cursor: 'invalid'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 400)
            .having(
              (error) => error.message,
              'message',
              'cursor 값이 올바르지 않습니다.',
            ),
      ),
    );
  });
}

ResponseBody _jsonResponse(
  RequestOptions request,
  int statusCode,
  Object body,
) {
  return ResponseBody.fromBytes(
    Uint8List.fromList(utf8.encode(jsonEncode(body))),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
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
