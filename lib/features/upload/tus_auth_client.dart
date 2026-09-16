import 'package:http/http.dart' as http;

typedef AccessTokenReader = Future<String?> Function();
typedef SessionRefresher = Future<void> Function();

/// tus 요청마다 최신 access token을 주입하고 401이면 기존 인증 갱신 경로를 호출.
class TusAuthClient extends http.BaseClient {
  TusAuthClient({
    required this.inner,
    required this.readAccessToken,
    required this.refreshSession,
  });

  final http.Client inner;
  final AccessTokenReader readAccessToken;
  final SessionRefresher refreshSession;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _sendAuthorized(request);

    if (response.statusCode != 401) {
      return response;
    }

    await response.stream.drain<void>();
    await refreshSession();

    // tus 생성 POST와 오프셋 HEAD는 본문이 없어 토큰 갱신 후 재요청 가능.
    if (_canReplay(request)) {
      return _sendAuthorized(_copyEmptyRequest(request));
    }

    // PATCH 본문은 재사용할 수 없으므로 tus 재시도 경로로 위임.
    // 서버 오프셋 확인 후 동일 청크를 새 토큰으로 재전송.
    throw http.ClientException('access token 갱신 후 tus 요청 재시도', request.url);
  }

  Future<http.StreamedResponse> _sendAuthorized(
    http.BaseRequest request,
  ) async {
    final accessToken = await readAccessToken();

    if (accessToken == null) {
      throw http.ClientException('로그인이 필요합니다.', request.url);
    }

    request.headers['Authorization'] = 'Bearer $accessToken';

    return inner.send(request);
  }

  static bool _canReplay(http.BaseRequest request) {
    return request.contentLength == 0 &&
        (request.method == 'POST' || request.method == 'HEAD');
  }

  static http.Request _copyEmptyRequest(http.BaseRequest request) {
    return http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection;
  }

  @override
  void close() => inner.close();
}
