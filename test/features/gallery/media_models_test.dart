import 'package:baby_gallery/features/gallery/media_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('미디어 목록 응답을 파싱한다', () {
    final page = MediaPage.fromJson({
      'items': [
        {
          'id': 7,
          'mediaType': 'Video',
          'fileName': 'clip.mov',
          'fileSize': 123456,
          'capturedAt': '2026-08-24T03:04:05Z',
          'width': 1920,
          'height': 1080,
          'durationMs': 4200,
        },
      ],
      'nextCursor': 'next-page',
    });

    expect(page.items, hasLength(1));
    expect(page.nextCursor, 'next-page');

    final item = page.items.single;

    expect(item.id, 7);
    expect(item.mediaType, MediaType.video);
    expect(item.fileName, 'clip.mov');
    expect(item.fileSize, 123456);
    expect(item.capturedAt, DateTime.utc(2026, 8, 24, 3, 4, 5));
    expect(item.capturedAt.isUtc, isTrue);
    expect(item.width, 1920);
    expect(item.height, 1080);
    expect(item.durationMs, 4200);
  });

  test('선택 메타데이터와 마지막 페이지의 null 값을 허용한다', () {
    final page = MediaPage.fromJson({
      'items': [
        {
          'id': 8,
          'mediaType': 'Image',
          'fileName': 'photo.jpg',
          'fileSize': 100,
          'capturedAt': '2026-08-24T12:00:00+09:00',
          'width': null,
          'height': null,
          'durationMs': null,
        },
      ],
      'nextCursor': null,
    });

    final item = page.items.single;

    expect(page.nextCursor, isNull);
    expect(item.mediaType, MediaType.image);
    expect(item.capturedAt, DateTime.utc(2026, 8, 24, 3));
    expect(item.width, isNull);
    expect(item.height, isNull);
    expect(item.durationMs, isNull);
  });

  test('알 수 없는 미디어 타입을 거부한다', () {
    expect(() => MediaType.parse('Audio'), throwsFormatException);
  });
}
