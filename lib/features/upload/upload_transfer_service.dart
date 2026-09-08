import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:tusc/tusc.dart';

import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/app_config.dart';
import '../../core/token_storage.dart';
import 'tus_auth_client.dart';
import 'upload_models.dart';
import 'upload_repository.dart';

const int uploadChunkSize = 5 * 1024 * 1024;

typedef UploadProgressCallback = void Function(int sentBytes, int totalBytes);

abstract interface class UploadTransport {
  Future<Uri> send(PreparedUpload upload, {UploadProgressCallback? onProgress});
}

class TusUploadTransport implements UploadTransport {
  TusUploadTransport({
    required this.endpoint,
    required this.cache,
    required this.httpClient,
    this.retryDelays = TusBaseClient.defaultRetryDelays,
  });

  final Uri endpoint;
  final TusCache cache;
  final http.Client httpClient;
  final List<Duration> retryDelays;

  @override
  Future<Uri> send(
    PreparedUpload upload, {
    UploadProgressCallback? onProgress,
  }) async {
    final file = File(upload.source.path);
    final client = _ContentHashTusClient(
      endpoint: endpoint,
      file: file,
      upload: upload,
      cache: cache,
      httpClient: httpClient,
      retryDelays: retryDelays,
    );

    try {
      await client.startUpload(
        onProgress: (sent, total, response) => onProgress?.call(sent, total),
      );

      if (client.state != TusUploadState.completed) {
        throw StateError('업로드가 완료되지 않았습니다.');
      }

      return Uri.parse(client.uploadUrl);
    } on ProtocolException catch (error) {
      throw ApiException(_messageOf(error), statusCode: error.statusCode);
    } on http.ClientException {
      throw const ApiException('서버에 연결할 수 없습니다.');
    } on TimeoutException {
      throw const ApiException('업로드 응답이 지연되고 있습니다.');
    } on DioException catch (error) {
      throw ApiException.from(error);
    } finally {
      client.close();
    }
  }

  static String _messageOf(ProtocolException error) {
    final body = error.response?.body;

    if (body != null && body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);

        if (decoded is Map && decoded['detail'] is String) {
          final detail = decoded['detail'] as String;

          if (detail.trim().isNotEmpty) {
            return detail;
          }
        }
      } on FormatException {
        // problem+json이 아닌 tus 응답은 상태별 기본 문구로 처리.
      }
    }

    return switch (error.statusCode) {
      401 => '로그인이 필요합니다.',
      403 => '업로드 권한이 없습니다.',
      413 => '업로드할 파일이 너무 큽니다.',
      _ => '파일을 업로드하지 못했습니다.',
    };
  }
}

class UploadTransferService {
  UploadTransferService(this._transport, this._repository);

  final UploadTransport _transport;
  final UploadRepository _repository;

  Future<UploadCommitResult> transfer(
    PreparedUpload upload, {
    UploadProgressCallback? onProgress,
  }) async {
    final existingMediaId = upload.existingMediaId;

    if (existingMediaId != null) {
      return UploadCommitResult(mediaId: existingMediaId, isDuplicate: true);
    }

    final uploadUri = await _transport.send(upload, onProgress: onProgress);
    final fileId = _fileIdOf(uploadUri);

    return _repository.commit(fileId);
  }

  static String _fileIdOf(Uri uploadUri) {
    final fileId = uploadUri.pathSegments.isEmpty
        ? null
        : uploadUri.pathSegments.last;

    if (fileId == null || !RegExp(r'^[0-9a-f]{32}$').hasMatch(fileId)) {
      throw const FormatException('서버가 올바르지 않은 업로드 주소를 반환했습니다.');
    }

    return fileId;
  }
}

class _ContentHashTusClient extends TusStreamClient {
  _ContentHashTusClient({
    required Uri endpoint,
    required File file,
    required PreparedUpload upload,
    required TusCache cache,
    required http.Client httpClient,
    required List<Duration> retryDelays,
  }) : _contentHash = upload.contentHash,
       super(
         url: endpoint.toString(),
         fileStreamGenerator: file.openRead,
         fileSize: upload.fileSize,
         fileName: upload.source.fileName,
         chunkSize: uploadChunkSize,
         cache: cache,
         headers: const {'Accept': 'application/json'},
         metadata: {'contentHash': upload.contentHash},
         timeout: const Duration(minutes: 5),
         retryDelays: retryDelays,
         httpClient: httpClient,
       );

  final String _contentHash;

  // 같은 이름·크기의 파일이 바뀌어도 다른 세션으로 취급.
  @override
  String generateFingerprint() => '${url}_$_contentHash';
}

final tusCacheProvider = FutureProvider<TusCache>((ref) async {
  final supportDirectory = await getApplicationSupportDirectory();

  return TusPersistentCache(
    '${supportDirectory.path}${Platform.pathSeparator}upload-sessions',
  );
});

final tusHttpClientProvider = Provider<http.Client>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final dio = ref.watch(dioProvider);
  final client = TusAuthClient(
    inner: http.Client(),
    readAccessToken: storage.readAccessToken,
    // 만료 토큰이면 AuthInterceptor가 refresh 회전 후 /auth/me를 재요청.
    refreshSession: () async {
      await dio.get<Map<String, dynamic>>('/auth/me');
    },
  );

  ref.onDispose(client.close);

  return client;
});

final uploadTransportProvider = FutureProvider<UploadTransport>((ref) async {
  final baseUri = Uri.parse(AppConfig.apiBaseUrl);

  return TusUploadTransport(
    endpoint: baseUri.resolve('/media/uploads'),
    cache: await ref.watch(tusCacheProvider.future),
    httpClient: ref.watch(tusHttpClientProvider),
  );
});

final uploadTransferServiceProvider = FutureProvider<UploadTransferService>((
  ref,
) async {
  return UploadTransferService(
    await ref.watch(uploadTransportProvider.future),
    ref.watch(uploadRepositoryProvider),
  );
});
