import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:baby_gallery/core/token_storage.dart';
import 'package:baby_gallery/features/gallery/video_streaming.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dio HEAD 요청 후 최신 access token으로 영상 소스를 만든다', () async {
    late RequestOptions capturedRequest;
    final storage = _FakeTokenStorage('old-token');
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            storage.accessToken = 'fresh-token';
            handler.next(response);
          },
        ),
      )
      ..httpClientAdapter = _StubAdapter((request) {
        capturedRequest = request;

        return ResponseBody.fromBytes(const [], 200);
      });
    final loader = DioVideoStreamSourceLoader(dio, storage);

    final source = await loader.prepare(17);

    expect(capturedRequest.method, 'HEAD');
    expect(capturedRequest.path, '/media/17/original');
    expect(source.uri, Uri.parse('https://example.test/media/17/original'));
    expect(source.headers, {'Authorization': 'Bearer fresh-token'});
  });
}

class _FakeTokenStorage extends TokenStorage {
  _FakeTokenStorage(this.accessToken) : super(const FlutterSecureStorage());

  String? accessToken;

  @override
  Future<String?> readAccessToken() async => accessToken;
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
