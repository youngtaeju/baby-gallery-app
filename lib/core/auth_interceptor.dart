import 'package:dio/dio.dart';

import 'token_storage.dart';

enum _RefreshOutcome {
  // 새 토큰 발급 완료.
  renewed,

  // refresh token 만료·폐기. 재로그인 필요.
  rejected,

  // 네트워크 등 일시 실패. 저장분 유지.
  failed,
}

/// access token 주입과 401 응답 시 토큰 갱신 후 재요청.
///
/// 서버는 폐기된 refresh token의 재제시를 탈취로 간주해 해당 사용자의 세션 전체를 차단.
/// 동시 401이 각자 갱신을 호출하지 않도록 진행 중인 갱신 하나를 공유.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.refreshDio,
    required this.storage,
    required this.onSessionExpired,
  });

  // 401 재요청 대상. 이 인터셉터가 부착된 인스턴스.
  final Dio dio;

  // 갱신 요청 전용. 인터셉터 미부착.
  final Dio refreshDio;

  final TokenStorage storage;

  // 갱신 불가로 세션이 끝났을 때의 통지.
  final void Function() onSessionExpired;

  static const String _retriedKey = 'auth_retried';

  Future<_RefreshOutcome>? _refreshing;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final accessToken = await storage.readAccessToken();

    if (accessToken != null) {
      options.headers['Authorization'] = 'Bearer $accessToken';
    }

    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;

    if (err.response?.statusCode != 401 || options.extra[_retriedKey] == true) {
      handler.next(err);
      return;
    }

    final outcome = await _refresh();

    if (outcome != _RefreshOutcome.renewed) {
      if (outcome == _RefreshOutcome.rejected) {
        onSessionExpired();
      }

      handler.next(err);
      return;
    }

    options.extra[_retriedKey] = true;

    try {
      // 재요청도 인터셉터를 거치며 갱신된 토큰 주입. 본문이 스트림인 요청은 대상 밖.
      handler.resolve(await dio.fetch<dynamic>(options));
    } on DioException catch (error) {
      handler.next(error);
    }
  }

  Future<_RefreshOutcome> _refresh() {
    return _refreshing ??= _requestRefresh().whenComplete(
      () => _refreshing = null,
    );
  }

  Future<_RefreshOutcome> _requestRefresh() async {
    final refreshToken = await storage.readRefreshToken();

    if (refreshToken == null) {
      return _RefreshOutcome.rejected;
    }

    try {
      final response = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      final data = response.data;
      final renewedAccessToken = data?['accessToken'];
      final rotatedRefreshToken = data?['refreshToken'];

      if (renewedAccessToken is! String || rotatedRefreshToken is! String) {
        return _RefreshOutcome.failed;
      }

      await storage.save(
        accessToken: renewedAccessToken,
        refreshToken: rotatedRefreshToken,
      );

      return _RefreshOutcome.renewed;
    } on DioException catch (error) {
      // 401만 만료·폐기 확정. 나머지는 일시 오류로 보고 저장분 유지.
      if (error.response?.statusCode != 401) {
        return _RefreshOutcome.failed;
      }

      await storage.clear();

      return _RefreshOutcome.rejected;
    }
  }
}
