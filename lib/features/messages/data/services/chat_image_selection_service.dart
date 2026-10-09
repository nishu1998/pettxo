import 'package:image_picker/image_picker.dart';

const int maxChatImageSourceBytes = 10 * 1024 * 1024;

abstract interface class ChatImagePickerDelegate {
  Future<XFile?> pickFromGallery();
  Future<LostDataResponse> retrieveLostData();
}

class PluginChatImagePickerDelegate implements ChatImagePickerDelegate {
  PluginChatImagePickerDelegate({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<XFile?> pickFromGallery() => _picker.pickImage(
    source: ImageSource.gallery,
    imageQuality: 100,
    requestFullMetadata: false,
  );

  @override
  Future<LostDataResponse> retrieveLostData() => _picker.retrieveLostData();
}

class ChatImageSelectionException implements Exception {
  const ChatImageSelectionException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ChatImageSelectionService {
  ChatImageSelectionService({ChatImagePickerDelegate? picker})
    : _picker = picker ?? PluginChatImagePickerDelegate();

  final ChatImagePickerDelegate _picker;

  Future<XFile?> selectSingleImage() async {
    try {
      final recovered = await _recoverLostImage();
      final selected = recovered ?? await _picker.pickFromGallery();
      if (selected == null) return null;
      final length = await selected.length();
      if (length <= 0) {
        throw const ChatImageSelectionException('The selected image is empty.');
      }
      if (length > maxChatImageSourceBytes) {
        throw const ChatImageSelectionException(
          'Please choose an image smaller than 10 MB.',
        );
      }
      return selected;
    } on ChatImageSelectionException {
      rethrow;
    } catch (_) {
      throw const ChatImageSelectionException(
        'Unable to open that image. Please choose another photo.',
      );
    }
  }

  Future<XFile?> _recoverLostImage() async {
    final response = await _picker.retrieveLostData();
    if (response.isEmpty) return null;
    if (response.exception != null) {
      throw const ChatImageSelectionException(
        'Pettxo could not recover the previously selected image.',
      );
    }
    final files = response.files;
    return files == null || files.isEmpty ? null : files.first;
  }
}
