import 'package:family_gallery/app.dart';
import 'package:family_gallery/features/auth/auth_controller.dart';
import 'package:family_gallery/features/auth/auth_models.dart';
import 'package:family_gallery/features/gallery/media_list_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// 저장된 토큰 조회를 건너뛰고 인증 상태만 고정.
class _FixedAuthController extends AuthController {
  _FixedAuthController(this._user);

  final AuthUser? _user;

  @override
  Future<AuthUser?> build() async => _user;
}

class _EmptyMediaListController extends MediaListController {
  @override
  Future<MediaListState> build() async {
    return MediaListState(items: [], nextCursor: null);
  }
}

Future<void> _pumpApp(WidgetTester tester, AuthUser? user) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _FixedAuthController(user)),
        mediaListControllerProvider.overrideWith(_EmptyMediaListController.new),
      ],
      child: const FamilyGalleryApp(),
    ),
  );

  // 인증·미디어 목록의 비동기 build 완료 대기.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('미로그인 상태에서 로그인 화면 표시', (tester) async {
    await _pumpApp(tester, null);

    expect(find.text('로그인'), findsOneWidget);
  });

  testWidgets('로그인 상태에서 갤러리 화면 표시', (tester) async {
    await _pumpApp(
      tester,
      const AuthUser(
        id: 1,
        username: 'tester',
        displayName: '테스터',
        role: UserRole.viewer,
      ),
    );

    expect(find.text('가족 갤러리'), findsOneWidget);
    expect(find.text('아직 미디어가 없습니다.'), findsOneWidget);
  });
}
