import 'package:dio/dio.dart';

/// API 호출 실패의 앱 공용 표현.
///
/// 서버 실패 응답은 problem+json 형식.
/// `detail`의 사용자 대상 한국어 메시지 우선, 부재 시 상태·오류 유형별 기본 문구로 대체.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  factory ApiException.from(DioException error) {
    final response = error.response;

    if (response == null) {
      return ApiException(_transportMessage(error.type));
    }

    return ApiException(
      _detailOf(response.data) ?? _statusMessage(response.statusCode),
      statusCode: response.statusCode,
    );
  }

  final String message;

  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;

  static String? _detailOf(Object? data) {
    if (data is! Map) {
      return null;
    }

    final detail = data['detail'];

    return detail is String && detail.trim().isNotEmpty ? detail : null;
  }

  static String _statusMessage(int? statusCode) {
    return switch (statusCode) {
      401 => '로그인이 필요합니다.',
      403 => '권한이 없습니다.',
      404 => '요청한 항목을 찾을 수 없습니다.',
      final int status when status >= 500 => '서버에 문제가 발생했습니다. 잠시 후 다시 시도해 주세요.',
      _ => '요청을 처리하지 못했습니다.',
    };
  }

  static String _transportMessage(DioExceptionType type) {
    return switch (type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => '서버 응답이 지연되고 있습니다.',
      DioExceptionType.connectionError => '서버에 연결할 수 없습니다.',
      DioExceptionType.badCertificate => '서버 인증서를 확인할 수 없습니다.',
      DioExceptionType.cancel => '요청이 취소되었습니다.',
      _ => '네트워크 오류가 발생했습니다.',
    };
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
