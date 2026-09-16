import 'package:baby_gallery/features/upload/upload_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('중복 조회 결과에서 업로드 필요 여부를 구분한다', () {
    final duplicate = UploadLookupResult.fromJson({
      'hash': 'a' * 64,
      'mediaId': 17,
    });
    final newMedia = UploadLookupResult.fromJson({
      'hash': 'b' * 64,
      'mediaId': null,
    });

    expect(duplicate.isDuplicate, isTrue);
    expect(duplicate.mediaId, 17);
    expect(newMedia.isDuplicate, isFalse);
    expect(newMedia.mediaId, isNull);
  });

  test('편입 결과의 완료 시점 중복 여부를 파싱한다', () {
    final result = UploadCommitResult.fromJson({
      'mediaId': 23,
      'duplicate': true,
    });

    expect(result.mediaId, 23);
    expect(result.isDuplicate, isTrue);
  });
}
