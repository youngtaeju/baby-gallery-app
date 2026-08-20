/// 서버 `UserRole`에 대응. 조회 범위는 동일하고 쓰기 작업만 구분.
enum UserRole {
  viewer,
  editor;

  // 서버 응답은 PascalCase 문자열. 미지의 값은 최소 권한으로 처리.
  static UserRole parse(Object? value) {
    return value is String && value.toLowerCase() == 'editor'
        ? UserRole.editor
        : UserRole.viewer;
  }
}

class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String,
      displayName: json['displayName'] as String,
      role: UserRole.parse(json['role']),
    );
  }

  final int id;

  final String username;

  final String displayName;

  final UserRole role;

  // 업로드·삭제 UI 노출 조건. 실제 차단은 서버 책임.
  bool get canEdit => role == UserRole.editor;
}

/// 로그인·토큰 갱신 응답.
///
/// 응답의 `expiresIn`은 미사용. 선제 갱신 없이 401 응답 기준으로 갱신.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  final String accessToken;

  final String refreshToken;

  final AuthUser user;
}
