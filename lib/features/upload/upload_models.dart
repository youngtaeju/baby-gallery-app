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
