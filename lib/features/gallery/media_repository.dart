import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import 'media_models.dart';

class MediaRepository {
  MediaRepository(this._dio);

  final Dio _dio;

  Future<MediaPage> list({String? cursor, int? limit}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/media',
        queryParameters: {'cursor': ?cursor, 'limit': ?limit},
      );

      final data = response.data;

      if (data == null) {
        throw const ApiException('서버 응답이 비어 있습니다.');
      }

      return MediaPage.fromJson(data);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }
}

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(ref.watch(dioProvider));
});
