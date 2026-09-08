import 'dart:async';

import 'package:baby_gallery/features/upload/tus_auth_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('tus 요청마다 최신 access token을 주입한다', () async {
    var token = 'first-token';
    final receivedTokens = <String?>[];
    final client = TusAuthClient(
      inner: _CallbackClient((request) {
        receivedTokens.add(request.headers['Authorization']);
        return _response(204);
      }),
      readAccessToken: () async => token,
      refreshSession: () async {},
    );

    await client.head(Uri.parse('https://example.test/upload/1'));
    token = 'second-token';
    await client.head(Uri.parse('https://example.test/upload/1'));

    expect(receivedTokens, ['Bearer first-token', 'Bearer second-token']);
  });

  test('본문 없는 생성 요청은 401 갱신 후 즉시 재요청한다', () async {
    var token = 'expired-token';
    var refreshCount = 0;
    final receivedTokens = <String?>[];
    final client = TusAuthClient(
      inner: _CallbackClient((request) {
        receivedTokens.add(request.headers['Authorization']);

        return _response(receivedTokens.length == 1 ? 401 : 201);
      }),
      readAccessToken: () async => token,
      refreshSession: () async {
        refreshCount++;
        token = 'renewed-token';
      },
    );

    final response = await client.post(
      Uri.parse('https://example.test/media/uploads'),
    );

    expect(response.statusCode, 201);
    expect(refreshCount, 1);
    expect(receivedTokens, ['Bearer expired-token', 'Bearer renewed-token']);
  });

  test('소비된 PATCH는 401 갱신 후 tus 재시도용 오류를 반환한다', () async {
    var token = 'expired-token';
    var refreshCount = 0;
    final client = TusAuthClient(
      inner: _CallbackClient((request) => _response(401)),
      readAccessToken: () async => token,
      refreshSession: () async {
        refreshCount++;
        token = 'renewed-token';
      },
    );
    final request = http.Request(
      'PATCH',
      Uri.parse('https://example.test/media/uploads/1'),
    )..bodyBytes = const [1, 2, 3];

    await expectLater(
      client.send(request),
      throwsA(isA<http.ClientException>()),
    );
    expect(refreshCount, 1);
    expect(token, 'renewed-token');
  });
}

http.StreamedResponse _response(int statusCode) {
  return http.StreamedResponse(const Stream<List<int>>.empty(), statusCode);
}

class _CallbackClient extends http.BaseClient {
  _CallbackClient(this._handler);

  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return _handler(request);
  }
}
