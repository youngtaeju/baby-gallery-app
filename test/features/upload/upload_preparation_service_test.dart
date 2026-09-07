import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baby_gallery/features/upload/upload_models.dart';
import 'package:baby_gallery/features/upload/upload_preparation_service.dart';
import 'package:baby_gallery/features/upload/upload_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('파일을 스트리밍 해시하고 중복 조회 결과를 연결한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'baby-gallery-upload-',
    );
    final first = File('${directory.path}${Platform.pathSeparator}first.jpg');
    final second = File('${directory.path}${Platform.pathSeparator}second.mp4');
    await first.writeAsBytes(utf8.encode('abc'));
    await second.writeAsBytes(const [0, 1, 2, 3]);
    addTearDown(() async {
      await first.delete();
      await second.delete();
      await directory.delete();
    });

    late List<dynamic> requestedHashes;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter((request) {
        requestedHashes =
            (request.data as Map<String, dynamic>)['hashes'] as List<dynamic>;

        return _jsonResponse(request, 200, {
          'results': [
            {'hash': requestedHashes[0], 'mediaId': 7},
            {'hash': requestedHashes[1], 'mediaId': null},
          ],
        });
      });
    final service = UploadPreparationService(UploadRepository(dio));

    final uploads = await service.prepare([
      LocalUploadFile(path: first.path, fileName: '첫 사진.jpg'),
      LocalUploadFile(path: second.path, fileName: '영상.mp4'),
    ]);

    expect(requestedHashes, [
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      '054edec1d0211f624fed0cbca9d4f9400b0e491c43742af2c5b0abebf0c990d8',
    ]);
    expect(uploads[0].source.fileName, '첫 사진.jpg');
    expect(uploads[0].fileSize, 3);
    expect(uploads[0].existingMediaId, 7);
    expect(uploads[0].needsUpload, isFalse);
    expect(uploads[1].fileSize, 4);
    expect(uploads[1].existingMediaId, isNull);
    expect(uploads[1].needsUpload, isTrue);
  });

  test('빈 선택은 서버를 호출하지 않고 종료한다', () async {
    var requestCount = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter((request) {
        requestCount++;
        return _jsonResponse(request, 500, const {});
      });

    final uploads = await UploadPreparationService(
      UploadRepository(dio),
    ).prepare(const []);

    expect(uploads, isEmpty);
    expect(requestCount, 0);
  });

  test('서버 상한을 넘는 파일 선택을 조회 전에 거부한다', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    final sources = List.generate(
      maxUploadSelectionCount + 1,
      (index) => LocalUploadFile(path: '$index', fileName: '$index.jpg'),
    );

    expect(
      () => UploadPreparationService(UploadRepository(dio)).prepare(sources),
      throwsArgumentError,
    );
  });

  test('서버 응답의 해시 순서가 다르면 거부한다', () async {
    final directory = await Directory.systemTemp.createTemp(
      'baby-gallery-upload-',
    );
    final file = File('${directory.path}${Platform.pathSeparator}photo.jpg');
    await file.writeAsBytes(utf8.encode('abc'));
    addTearDown(() async {
      await file.delete();
      await directory.delete();
    });

    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StubAdapter(
        (request) => _jsonResponse(request, 200, {
          'results': [
            {'hash': 'f' * 64, 'mediaId': null},
          ],
        }),
      );

    expect(
      () => UploadPreparationService(
        UploadRepository(dio),
      ).prepare([LocalUploadFile(path: file.path, fileName: 'photo.jpg')]),
      throwsFormatException,
    );
  });
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

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._handler);

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
