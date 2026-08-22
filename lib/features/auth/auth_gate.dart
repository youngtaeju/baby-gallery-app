import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../gallery/gallery_page.dart';
import 'auth_controller.dart';
import 'login_page.dart';

/// 인증 상태에 따른 최상위 화면 분기.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(authControllerProvider)
        .when(
          loading: () =>
              const _BootstrapScaffold(child: CircularProgressIndicator()),
          error: (error, stackTrace) => _BootstrapScaffold(
            child: _BootstrapFailure(
              message: error is ApiException ? error.message : '앱을 시작하지 못했습니다.',
              onRetry: () => ref.invalidate(authControllerProvider),
            ),
          ),
          data: (user) =>
              user == null ? const LoginPage() : const GalleryPage(),
        );
  }
}

class _BootstrapScaffold extends StatelessWidget {
  const _BootstrapScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    );
  }
}

/// 토큰 검증 실패 화면.
///
/// 네트워크 오류로 세션을 잃지 않도록 로그아웃 대신 재시도를 제공.
class _BootstrapFailure extends StatelessWidget {
  const _BootstrapFailure({required this.message, required this.onRetry});

  final String message;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    );
  }
}
