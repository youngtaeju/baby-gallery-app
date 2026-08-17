# family-gallery-app

가정용 시놀로지 NAS의 이미지·영상을 가족 구성원만 조회하는 갤러리 앱. Android APK 배포.

- 미디어 조회 전용. 업로드·수정·삭제 기능 없음
- 백엔드는 `family-gallery-api` 단독. 통신은 HTTPS만 허용
- 모든 사용자 동일한 `viewer` 권한. 역할 구분 없음

## 요구 사항

- Flutter 3.44 이상 (Dart 3.12)
- Android SDK / JDK 17

## 프로젝트 구조

```
lib/
  main.dart              ProviderScope 진입점
  app.dart               MaterialApp, 테마
  core/                  기능에 묶이지 않는 공통 인프라
    app_config.dart      빌드 시점 주입 설정
    api_client.dart      Dio 인스턴스 provider
    token_storage.dart   access / refresh token 보관소
  features/              기능 단위 폴더. 화면·상태·API 호출을 같은 위치에 배치
android/                 Android 전용 빌드 설정
test/
```

상태 관리는 Riverpod, HTTP는 Dio, 토큰 보관은 flutter_secure_storage.

## 설정

| 키 | 설명 | 기본값 |
| --- | --- | --- |
| `API_BASE_URL` | API 서버 주소 | `https://family-gallery.kyleju.com` |

빌드 시점에 `--dart-define`으로 주입. 미지정 시 기본값 사용.

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5088
flutter build apk --release --dart-define=API_BASE_URL=https://family-gallery.kyleju.com
```

Android 에뮬레이터에서 호스트의 로컬 API를 호출할 때는 `10.0.2.2`가 호스트 loopback에 대응.

## 로컬 실행

```bash
flutter pub get
flutter run
```

검증:

```bash
flutter analyze
flutter test
flutter build apk --debug
```

## 라이선스

[MIT](./LICENSE)
