import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../../core/token_storage.dart';
import 'auth_models.dart';
import 'auth_repository.dart';

/// 인증 상태. 값이 null이면 미로그인.
///
/// 부팅 시 저장된 토큰으로 사용자 조회. 네트워크 실패는 오류 상태로 남겨
/// 오프라인을 로그아웃으로 처리하지 않음.
class AuthController extends AsyncNotifier<AuthUser?> {
  @override
  Future<AuthUser?> build() async {
    final storage = ref.read(tokenStorageProvider);

    if (await storage.readAccessToken() == null) {
      return null;
    }

    try {
      return await ref.read(authRepositoryProvider).me();
    } on ApiException catch (error) {
      if (!error.isUnauthorized) {
        rethrow;
      }

      // 인터셉터의 갱신까지 실패한 401. 저장분 폐기.
      await storage.clear();

      return null;
    }
  }

  /// 로그인 시도. 실패는 호출한 화면이 표시하도록 그대로 전파.
  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    final session = await ref
        .read(authRepositoryProvider)
        .login(username: username, password: password);

    await ref
        .read(tokenStorageProvider)
        .save(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
        );

    state = AsyncData(session.user);
  }

  Future<void> signOut() async {
    final storage = ref.read(tokenStorageProvider);
    final refreshToken = await storage.readRefreshToken();

    if (refreshToken != null) {
      try {
        await ref
            .read(authRepositoryProvider)
            .logout(refreshToken: refreshToken);
      } on ApiException {
        // 서버 폐기 실패와 무관하게 로컬 세션 종료. 남은 토큰은 만료로 정리.
      }
    }

    await storage.clear();

    state = const AsyncData(null);
  }

  /// 토큰 갱신 실패로 인한 세션 종료. AuthInterceptor에서 호출.
  void expire() {
    if (!ref.mounted) {
      return;
    }

    state = const AsyncData(null);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthUser?>(
  AuthController.new,
);
