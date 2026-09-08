class LocalUploadFile {
  const LocalUploadFile({required this.path, required this.fileName});

  final String path;

  final String fileName;
}

class PreparedUpload {
  const PreparedUpload({
    required this.source,
    required this.fileSize,
    required this.contentHash,
    required this.existingMediaId,
  });

  final LocalUploadFile source;

  final int fileSize;

  final String contentHash;

  final int? existingMediaId;

  bool get needsUpload => existingMediaId == null;
}

enum UploadJobStatus {
  pending,
  uploading,
  completed,
  failed;

  static UploadJobStatus parse(Object? value) {
    return UploadJobStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => throw const FormatException('알 수 없는 업로드 상태입니다.'),
    );
  }
}

class UploadJob {
  const UploadJob({
    required this.upload,
    required this.status,
    this.sentBytes = 0,
    this.mediaId,
    this.isDuplicate = false,
    this.errorMessage,
  });

  factory UploadJob.fromJson(
    Map<String, dynamic> json, {
    required String sourcePath,
  }) {
    final existingMediaId = (json['existingMediaId'] as num?)?.toInt();

    return UploadJob(
      upload: PreparedUpload(
        source: LocalUploadFile(
          path: sourcePath,
          fileName: json['fileName'] as String,
        ),
        fileSize: (json['fileSize'] as num).toInt(),
        contentHash: json['contentHash'] as String,
        existingMediaId: existingMediaId,
      ),
      status: UploadJobStatus.parse(json['status']),
      sentBytes: (json['sentBytes'] as num?)?.toInt() ?? 0,
      mediaId: (json['mediaId'] as num?)?.toInt(),
      isDuplicate: json['isDuplicate'] as bool? ?? false,
      errorMessage: json['errorMessage'] as String?,
    );
  }

  final PreparedUpload upload;

  String get id => upload.contentHash;

  final UploadJobStatus status;

  final int sentBytes;

  final int? mediaId;

  final bool isDuplicate;

  final String? errorMessage;

  Map<String, dynamic> toJson() {
    return {
      'fileName': upload.source.fileName,
      'fileSize': upload.fileSize,
      'contentHash': upload.contentHash,
      'existingMediaId': upload.existingMediaId,
      'status': status.name,
      'sentBytes': sentBytes,
      'mediaId': mediaId,
      'isDuplicate': isDuplicate,
      'errorMessage': errorMessage,
    };
  }
}

class UploadLookupResult {
  const UploadLookupResult({required this.hash, required this.mediaId});

  factory UploadLookupResult.fromJson(Map<String, dynamic> json) {
    return UploadLookupResult(
      hash: json['hash'] as String,
      mediaId: (json['mediaId'] as num?)?.toInt(),
    );
  }

  final String hash;

  // null이면 서버에 같은 내용의 미디어가 없어 업로드 필요.
  final int? mediaId;

  bool get isDuplicate => mediaId != null;
}

class UploadCommitResult {
  const UploadCommitResult({required this.mediaId, required this.isDuplicate});

  factory UploadCommitResult.fromJson(Map<String, dynamic> json) {
    return UploadCommitResult(
      mediaId: (json['mediaId'] as num).toInt(),
      isDuplicate: json['duplicate'] as bool,
    );
  }

  final int mediaId;

  // 동시 업로드 경합으로 완료 시점에 중복 판정된 경우.
  final bool isDuplicate;
}
