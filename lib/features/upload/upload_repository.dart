import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import 'upload_models.dart';

class UploadRepository {
  UploadRepository(this._dio);

  final Dio _dio;

  Future<List<UploadLookupResult>> lookup(List<String> hashes) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/media/uploads/lookup',
        data: {'hashes': hashes},
      );
      final data = _requireBody(response);

      return (data['results'] as List<dynamic>)
          .map(
            (result) =>
                UploadLookupResult.fromJson(result as Map<String, dynamic>),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  Future<UploadCommitResult> commit(String fileId) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/media/uploads/$fileId/commit',
      );

      return UploadCommitResult.fromJson(_requireBody(response));
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  static Map<String, dynamic> _requireBody(
    Response<Map<String, dynamic>> response,
  ) {
    final data = response.data;

    if (data == null) {
      throw const ApiException('서버 응답이 비어 있습니다.');
    }

    return data;
  }
}

final uploadRepositoryProvider = Provider<UploadRepository>((ref) {
  return UploadRepository(ref.watch(dioProvider));
});
