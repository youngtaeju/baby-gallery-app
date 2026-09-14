import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'upload_models.dart';
import 'upload_preparation_service.dart';

abstract interface class UploadFilePicker {
  Future<List<LocalUploadFile>> pickFiles();

  Future<List<LocalUploadFile>> retrieveLostFiles();
}

class ImagePickerUploadFilePicker implements UploadFilePicker {
  ImagePickerUploadFilePicker(this._picker);

  final ImagePicker _picker;

  @override
  Future<List<LocalUploadFile>> pickFiles() async {
    final files = await _picker.pickMultipleMedia(
      limit: maxUploadSelectionCount,
      requestFullMetadata: false,
    );

    return _toLocalFiles(files);
  }

  @override
  Future<List<LocalUploadFile>> retrieveLostFiles() async {
    final response = await _picker.retrieveLostData();

    if (response.isEmpty) {
      return const [];
    }

    final exception = response.exception;

    if (exception != null) {
      throw exception;
    }

    final files = response.files;

    if (files != null) {
      return _toLocalFiles(files);
    }

    final file = response.file;
    return file == null ? const [] : _toLocalFiles([file]);
  }

  static List<LocalUploadFile> _toLocalFiles(List<XFile> files) {
    return files
        .map(
          (file) =>
              LocalUploadFile(path: file.path, fileName: _fileNameOf(file)),
        )
        .toList(growable: false);
  }

  static String _fileNameOf(XFile file) {
    final name = file.name.isEmpty ? file.path : file.name;
    return name.replaceAll('\\', '/').split('/').last;
  }
}

final uploadFilePickerProvider = Provider<UploadFilePicker>((ref) {
  return ImagePickerUploadFilePicker(ImagePicker());
});
