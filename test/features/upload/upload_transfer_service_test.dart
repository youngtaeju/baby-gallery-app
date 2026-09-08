import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baby_gallery/core/api_exception.dart';
import 'package:baby_gallery/features/upload/upload_models.dart';
import 'package:baby_gallery/features/upload/upload_repository.dart';
import 'package:baby_gallery/features/upload/upload_transfer_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tusc/tusc.dart' hide Headers;

const _fileId = '0123456789abcdef0123456789abcdef';

void main() {
  test('파일을 5MB 청크로 전송하고 contentHash 메타데이터를 보낸다', () async {
    final fixture = await _UploadFixture.create(uploadChunkSize + 3);
    addTearDown(fixture.dispose);
    final server = _TusServerClient();
    final progress = <int>[];
    final transport = TusUploadTransport(
      endpoint: Uri.parse('https://example.test/media/uploads'),
      cache: TusMemoryCache(),
      httpClient: server,
      retryDelays: const [],
    );

    final uploadUri = await transport.send(
      fixture.upload,
      onProgress: (sent, total) => progress.add(sent),
    );

    expect(uploadUri.pathSegments.last, _fileId);
    expect(server.createCount, 1);
    expect(server.createdLength, uploadChunkSize + 3);
    expect(server.createdMetadata, contains('contentHash '));
    expect(server.createdMetadata, contains('filename '));
    expect(server.chunkLengths, [uploadChunkSize, 3]);
    expect(
      progress,
      containsAllInOrder([0, uploadChunkSize, uploadChunkSize + 3]),
    );
  });

  test('중단된 세션은 서버 오프셋부터 이어서 전송한다', () async {
    final fixture = await _UploadFixture.create(uploadChunkSize + 3);
    addTearDown(fixture.dispose);
    final cache = TusMemoryCache();
    final server = _TusServerClient(failPatchNumber: 2);

    await expectLater(
      TusUploadTransport(
        endpoint: Uri.parse('https://example.test/media/uploads'),
        cache: cache,
        httpClient: server,
        retryDelays: const [],
      ).send(fixture.upload),
      throwsA(isA<ApiException>()),
    );

    expect(server.offset, uploadChunkSize);
    server.failPatchNumber = null;

    await TusUploadTransport(
      endpoint: Uri.parse('https://example.test/media/uploads'),
      cache: cache,
      httpClient: server,
      retryDelays: const [],
    ).send(fixture.upload);

    expect(server.createCount, 1);
    expect(server.headOffsets, [0, uploadChunkSize]);
    expect(server.chunkLengths, [uploadChunkSize, 3, 3]);
    expect(server.offset, uploadChunkSize + 3);
  });

  test('신규 업로드 완료 후 URL의 fileId로 편입 요청한다', () async {
    late RequestOptions commitRequest;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _DioStubAdapter((request) {
        commitRequest = request;
        return _jsonResponse(request, 200, {'mediaId': 41, 'duplicate': false});
      });
    final transport = _StubTransport(
      Uri.parse('https://example.test/media/uploads/$_fileId'),
    );
    final service = UploadTransferService(transport, UploadRepository(dio));

    final result = await service.transfer(_preparedUpload());

    expect(transport.sendCount, 1);
    expect(commitRequest.path, '/media/uploads/$_fileId/commit');
    expect(result.mediaId, 41);
    expect(result.isDuplicate, isFalse);
  });

  test('기존 미디어는 전송과 편입 요청 없이 완료 처리한다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final transport = _StubTransport(
      Uri.parse('https://example.test/media/uploads/$_fileId'),
    );
    final service = UploadTransferService(transport, UploadRepository(dio));

    final result = await service.transfer(_preparedUpload(existingMediaId: 9));

    expect(transport.sendCount, 0);
    expect(result.mediaId, 9);
    expect(result.isDuplicate, isTrue);
  });

  test('서버가 반환한 업로드 URL의 fileId 형식을 검증한다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final service = UploadTransferService(
      _StubTransport(Uri.parse('https://example.test/media/uploads/invalid')),
      UploadRepository(dio),
    );

    expect(() => service.transfer(_preparedUpload()), throwsFormatException);
  });
}

PreparedUpload _preparedUpload({int? existingMediaId}) {
  return PreparedUpload(
    source: const LocalUploadFile(path: 'unused', fileName: 'photo.jpg'),
    fileSize: 3,
    contentHash: 'a' * 64,
    existingMediaId: existingMediaId,
  );
}

class _UploadFixture {
  _UploadFixture(this.directory, this.file, this.upload);

  final Directory directory;
  final File file;
  final PreparedUpload upload;

  static Future<_UploadFixture> create(int size) async {
    final directory = await Directory.systemTemp.createTemp(
      'baby-gallery-tus-',
    );
    final file = File('${directory.path}${Platform.pathSeparator}video.mp4');
    await file.writeAsBytes(Uint8List(size));

    return _UploadFixture(
      directory,
      file,
      PreparedUpload(
        source: LocalUploadFile(path: file.path, fileName: '영상.mp4'),
        fileSize: size,
        contentHash: 'a' * 64,
        existingMediaId: null,
      ),
    );
  }

  Future<void> dispose() async {
    await file.delete();
    await directory.delete();
  }
}

class _TusServerClient extends http.BaseClient {
  _TusServerClient({this.failPatchNumber});

  int? failPatchNumber;
  int createCount = 0;
  int patchCount = 0;
  int offset = 0;
  int? createdLength;
  String? createdMetadata;
  final List<int> headOffsets = [];
  final List<int> chunkLengths = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    switch (request.method) {
      case 'POST':
        createCount++;
        createdLength = int.parse(request.headers['Upload-Length']!);
        createdMetadata = request.headers['Upload-Metadata'];
        return _response(201, headers: {'location': '/media/uploads/$_fileId'});
      case 'HEAD':
        headOffsets.add(offset);
        return _response(
          200,
          headers: {
            'upload-offset': '$offset',
            'upload-length': '$createdLength',
          },
        );
      case 'PATCH':
        patchCount++;
        final chunk = await _readBytes(request);
        chunkLengths.add(chunk.length);

        if (patchCount == failPatchNumber) {
          return _response(503);
        }

        expect(request.headers['Upload-Offset'], '$offset');
        offset += chunk.length;
        return _response(204, headers: {'upload-offset': '$offset'});
      default:
        throw StateError('예상하지 않은 ${request.method} 요청입니다.');
    }
  }
}

Future<Uint8List> _readBytes(http.BaseRequest request) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.finalize()) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

http.StreamedResponse _response(
  int statusCode, {
  Map<String, String>? headers,
}) {
  return http.StreamedResponse(
    const Stream<List<int>>.empty(),
    statusCode,
    headers: headers ?? const {},
  );
}

class _StubTransport implements UploadTransport {
  _StubTransport(this.result);

  final Uri result;
  int sendCount = 0;

  @override
  Future<Uri> send(
    PreparedUpload upload, {
    UploadProgressCallback? onProgress,
  }) async {
    sendCount++;
    return result;
  }
}

ResponseBody _jsonResponse(
  RequestOptions request,
  int statusCode,
  Object body,
) {
  return ResponseBody.fromBytes(
    Uint8List.fromList(utf8.encode(jsonEncode(body))),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _DioStubAdapter implements HttpClientAdapter {
  _DioStubAdapter(this._handler);

  final ResponseBody Function(RequestOptions request) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
