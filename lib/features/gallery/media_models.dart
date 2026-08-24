enum MediaType {
  image,
  video;

  static MediaType parse(Object? value) {
    return switch (value) {
      final String value when value.toLowerCase() == 'image' => MediaType.image,
      final String value when value.toLowerCase() == 'video' => MediaType.video,
      _ => throw const FormatException('지원하지 않는 미디어 타입입니다.'),
    };
  }
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.mediaType,
    required this.fileName,
    required this.fileSize,
    required this.capturedAt,
    required this.width,
    required this.height,
    required this.durationMs,
  });

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    return MediaItem(
      id: (json['id'] as num).toInt(),
      mediaType: MediaType.parse(json['mediaType']),
      fileName: json['fileName'] as String,
      fileSize: (json['fileSize'] as num).toInt(),
      capturedAt: DateTime.parse(json['capturedAt'] as String).toUtc(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
    );
  }

  final int id;

  final MediaType mediaType;

  final String fileName;

  final int fileSize;

  final DateTime capturedAt;

  final int? width;

  final int? height;

  final int? durationMs;
}

class MediaPage {
  const MediaPage({required this.items, required this.nextCursor});

  factory MediaPage.fromJson(Map<String, dynamic> json) {
    return MediaPage(
      items: (json['items'] as List<dynamic>)
          .map((item) => MediaItem.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<MediaItem> items;

  final String? nextCursor;
}
