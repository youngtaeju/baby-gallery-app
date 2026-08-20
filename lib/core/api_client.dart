import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_config.dart';

BaseOptions _baseOptions() {
  return BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: AppConfig.connectTimeout,
    receiveTimeout: AppConfig.receiveTimeout,
    responseType: ResponseType.json,
  );
}

final dioProvider = Provider<Dio>((ref) {
  return Dio(_baseOptions());
});

/// 인증 인터셉터 미부착. 로그인·토큰 갱신 전용.
///
/// 갱신 요청이 인터셉터를 다시 탈 경우 401 처리 재귀.
final rawDioProvider = Provider<Dio>((ref) {
  return Dio(_baseOptions());
});
