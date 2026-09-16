import 'package:baby_gallery/features/upload/upload_file_picker.dart';
import 'package:baby_gallery/features/upload/upload_preparation_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  test('이미지와 영상을 최대 선택 수와 함께 원본 경로로 변환한다', () async {
    final imagePicker = _FakeImagePicker([
      XFile('/cache/첫 사진.jpg'),
      XFile('/cache/첫 영상.mp4'),
    ]);

    final files = await ImagePickerUploadFilePicker(imagePicker).pickFiles();

    expect(imagePicker.limit, maxUploadSelectionCount);
    expect(imagePicker.requestFullMetadata, isFalse);
    expect(files.map((file) => file.path), [
      '/cache/첫 사진.jpg',
      '/cache/첫 영상.mp4',
    ]);
    expect(files.map((file) => file.fileName), ['첫 사진.jpg', '첫 영상.mp4']);
  });

  test('Android에서 유실된 선택 결과를 복구한다', () async {
    final imagePicker = _FakeImagePicker(
      const [],
      lostResponse: LostDataResponse(file: XFile('/cache/recovered.jpg')),
    );

    final files = await ImagePickerUploadFilePicker(
      imagePicker,
    ).retrieveLostFiles();

    expect(files.single.path, '/cache/recovered.jpg');
    expect(files.single.fileName, 'recovered.jpg');
  });
}

class _FakeImagePicker extends ImagePicker {
  _FakeImagePicker(this.files, {this.lostResponse});

  final List<XFile> files;
  final LostDataResponse? lostResponse;
  int? limit;
  bool? requestFullMetadata;

  @override
  Future<List<XFile>> pickMultipleMedia({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async {
    this.limit = limit;
    this.requestFullMetadata = requestFullMetadata;
    return files;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    return lostResponse ?? LostDataResponse.empty();
  }
}
