/// 빌드 시점 주입 설정.
///
/// 오버라이드: `flutter build apk --dart-define=API_BASE_URL=https://...`
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://family-gallery.kyleju.com',
  );

  static const Duration connectTimeout = Duration(seconds: 10);

  // 영상 스트리밍은 Dio 미경유. 목록/인증 응답 기준.
  static const Duration receiveTimeout = Duration(seconds: 30);
}
