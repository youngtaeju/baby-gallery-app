# baby-gallery-app

가정용 시놀로지 NAS의 이미지·영상을 가족 구성원만 이용하는 Flutter 갤러리 앱. Android/iOS 지원.

- 로그인한 사용자는 전체 미디어 조회 가능
- 권한은 `viewer` / `editor` 2종. 업로드·삭제는 `editor`만 가능
- 백엔드는 `baby-gallery-api` 단독. 운영 통신은 HTTPS만 허용

## 요구 사항

- Flutter 3.44 이상 (Dart 3.12)
- Android: Android SDK / JDK 17
- iOS: Xcode

## 프로젝트 구조

```
lib/
  main.dart              ProviderScope 진입점
  app.dart               MaterialApp, 테마
  core/                  기능에 묶이지 않는 공통 인프라
    app_config.dart      빌드 시점 주입 설정
    api_client.dart      인증 인터셉터가 연결된 Dio provider
    auth_interceptor.dart access token 주입·갱신·재요청
    token_storage.dart   access / refresh token 보관소
  features/
    auth/                인증 모델·API·상태·화면
    gallery/             미디어 모델·목록 상태·썸네일·그리드 화면
android/                 Android 빌드 설정
ios/                     iOS 빌드 설정
test/
```

상태 관리는 Riverpod, HTTP는 Dio, 토큰 보관은 flutter_secure_storage.
썸네일은 `dio_cache_interceptor`와 파일 저장소를 통해 서버의 `Cache-Control`·`ETag`를 따름.

## 미디어 목록

- `GET /media`를 기본 50건씩 조회하고 `nextCursor`로 다음 페이지 연결
- 촬영일시는 기기 로컬 시각으로 변환해 날짜별 그룹 표시
- 썸네일은 기존 Dio 인증 흐름을 공유하므로 access token 만료 시 갱신 후 재요청
- 썸네일 캐시는 앱 전용 cache directory에 저장. 다른 GET 응답에는 캐시 정책 미적용
- HEIC·HEIF처럼 서버에서 썸네일을 제공하지 못하는 항목은 대체 아이콘 표시

## 설정

| 키 | 설명 | 기본값 |
| --- | --- | --- |
| `API_BASE_URL` | API 서버 주소 | `https://baby-gallery.kyleju.com` |

빌드 시점에 `--dart-define`으로 주입. 미지정 시 기본값 사용.

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5088
flutter build apk --release --dart-define=API_BASE_URL=https://baby-gallery.kyleju.com
flutter build ios --release --dart-define=API_BASE_URL=https://baby-gallery.kyleju.com
```

Android 에뮬레이터에서 호스트의 로컬 API를 호출할 때는 `10.0.2.2`가 호스트 loopback에 대응.
iOS Simulator에서 로컬 HTTP API를 사용하려면 `127.0.0.1`과 Debug 전용 App Transport Security 예외 설정 필요. 운영 통신은 HTTPS만 허용.

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
flutter build ios --simulator --debug
```

## 라이선스

[MIT](./LICENSE)
