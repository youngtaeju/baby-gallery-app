import 'dart:convert';
import 'dart:typed_data';

import 'package:baby_gallery/core/api_exception.dart';
import 'package:baby_gallery/features/upload/upload_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('해시 순서를 유지해 중복 미디어를 조회한다', () async {
    late RequestOptions capturedRequest;
    final hashes = ['a' * 64, 'b' * 64, 'a' * 64];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter((request) {
        capturedRequest = request;

        return _jsonResponse(request, 200, {
          'results': [
            {'hash': hashes[0], 'mediaId': 11},
            {'hash': hashes[1], 'mediaId': null},
            {'hash': hashes[2], 'mediaId': 11},
          ],
        });
      });

    final results = await UploadRepository(dio).lookup(hashes);

    expect(capturedRequest.path, '/media/uploads/lookup');
    expect(capturedRequest.method, 'POST');
    expect(capturedRequest.data, {'hashes': hashes});
    expect(results.map((result) => result.hash), hashes);
    expect(results.map((result) => result.mediaId), [11, null, 11]);
  });

  test('업로드 세션을 편입하고 미디어 ID를 반환한다', () async {
    late RequestOptions capturedRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter((request) {
        capturedRequest = request;

        return _jsonResponse(request, 200, {'mediaId': 31, 'duplicate': false});
      });

    final result = await UploadRepository(dio).commit('upload-file-id');

    expect(capturedRequest.path, '/media/uploads/upload-file-id/commit');
    expect(capturedRequest.method, 'POST');
    expect(result.mediaId, 31);
    expect(result.isDuplicate, isFalse);
  });

  test('업로드 API 실패를 앱 공용 예외로 변환한다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter(
        (request) =>
            _jsonResponse(request, 422, {'detail': '전송된 내용이 선언한 크기·해시와 다릅니다.'}),
      );

    expect(
      () => UploadRepository(dio).commit('upload-file-id'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 422)
            .having(
              (error) => error.message,
              'message',
              '전송된 내용이 선언한 크기·해시와 다릅니다.',
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
