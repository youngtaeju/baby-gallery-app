import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// access / refresh token 보관소. 플랫폼 보안 저장소 사용.
///
/// 요청마다 복호화가 발생하지 않도록 최초 조회분을 메모리에 유지.
class TokenStorage {
  TokenStorage(this._storage);

  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';

  final FlutterSecureStorage _storage;

  String? _accessToken;

  String? _refreshToken;

  bool _loaded = false;

  Future<String?> readAccessToken() async {
    await _ensureLoaded();

    return _accessToken;
  }

  Future<String?> readRefreshToken() async {
    await _ensureLoaded();

    return _refreshToken;
  }

  Future<void> save({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _loaded = true;

    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _loaded = true;

    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }

    try {
      _accessToken = await _storage.read(key: _accessTokenKey);
      _refreshToken = await _storage.read(key: _refreshTokenKey);
    } on PlatformException {
      // 기기 백업 복원·키 손상 시 복호화 실패. 저장분 폐기 후 재로그인 경로.
      _accessToken = null;
      _refreshToken = null;

      try {
        await clear();
      } on PlatformException {
        // 삭제 실패분은 다음 로그인 성공 시 덮어쓰기.
      }
    }

    _loaded = true;
  }
}

// Android EncryptedSharedPreferences / iOS Keychain 기본 옵션.
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return TokenStorage(const FlutterSecureStorage());
});
