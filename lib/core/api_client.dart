import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/auth_controller.dart';
import 'app_config.dart';
import 'auth_interceptor.dart';
import 'token_storage.dart';

BaseOptions _baseOptions() {
  return BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: AppConfig.connectTimeout,
    receiveTimeout: AppConfig.receiveTimeout,
    responseType: ResponseType.json,
  );
}

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(_baseOptions());

  dio.interceptors.add(
    AuthInterceptor(
      dio: dio,
      refreshDio: ref.watch(rawDioProvider),
      storage: ref.watch(tokenStorageProvider),
      // 콜백 시점에 조회. 생성 시점 참조는 provider 순환.
      onSessionExpired: () =>
          ref.read(authControllerProvider.notifier).expire(),
    ),
  );

  return dio;
});

/// 인증 인터셉터 미부착. 로그인·토큰 갱신 전용.
///
/// 갱신 요청이 인터셉터를 다시 탈 경우 401 처리 재귀.
final rawDioProvider = Provider<Dio>((ref) {
  return Dio(_baseOptions());
});
