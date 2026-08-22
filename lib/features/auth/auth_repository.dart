import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import 'auth_models.dart';

/// `/auth` 엔드포인트 호출만 담당. 토큰 보관과 인증 상태 전이는 AuthController.
class AuthRepository {
  AuthRepository(this._dio, this._rawDio);

  // Bearer 필요. 인증 인터셉터 경유.
  final Dio _dio;

  // 인증 불필요. 인터셉터 재귀 방지 목적의 미경유 인스턴스.
  final Dio _rawDio;

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _rawDio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'username': username, 'password': password},
      );

      return AuthSession.fromJson(_requireBody(response));
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<AuthUser> me() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/auth/me');

      return AuthUser.fromJson(_requireBody(response));
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// 서버 측 refresh token 폐기. 로컬 토큰 삭제는 호출자 책임.
  Future<void> logout({required String refreshToken}) async {
    try {
      await _dio.post<void>(
        '/auth/logout',
        data: {'refreshToken': refreshToken},
      );
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  static Map<String, dynamic> _requireBody(
    Response<Map<String, dynamic>> response,
  ) {
    final data = response.data;

    if (data == null) {
      throw const ApiException('서버 응답이 비어 있습니다.');
    }

    return data;
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(dioProvider), ref.watch(rawDioProvider));
});
