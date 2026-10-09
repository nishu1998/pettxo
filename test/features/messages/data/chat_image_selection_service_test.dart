import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pettexo/features/messages/data/services/chat_image_selection_service.dart';

class _FakePicker implements ChatImagePickerDelegate {
  _FakePicker({this.selected, this.error, this.lost});

  final XFile? selected;
  final Object? error;
  final LostDataResponse? lost;

  @override
  Future<XFile?> pickFromGallery() async {
    if (error != null) throw error!;
    return selected;
  }

  @override
  Future<LostDataResponse> retrieveLostData() async =>
      lost ?? LostDataResponse.empty();
}

void main() {
  test('returns null when gallery selection is cancelled', () async {
    final service = ChatImageSelectionService(picker: _FakePicker());
    expect(await service.selectSingleImage(), isNull);
  });

  test('returns one selected gallery image', () async {
    final file = XFile.fromData(Uint8List.fromList([1, 2, 3]));
    final service = ChatImageSelectionService(
      picker: _FakePicker(selected: file),
    );
    expect(await service.selectSingleImage(), same(file));
  });

  test('recovers Android lost picker data before opening gallery', () async {
    final file = XFile.fromData(Uint8List.fromList([4, 5, 6]));
    final service = ChatImageSelectionService(
      picker: _FakePicker(
        lost: LostDataResponse(files: [file], type: RetrieveType.image),
      ),
    );
    expect(await service.selectSingleImage(), same(file));
  });

  test('maps picker failures to a useful selection exception', () async {
    final service = ChatImageSelectionService(
      picker: _FakePicker(error: StateError('picker failed')),
    );
    await expectLater(
      service.selectSingleImage(),
      throwsA(isA<ChatImageSelectionException>()),
    );
  });

  test('rejects an empty selected file', () async {
    final service = ChatImageSelectionService(
      picker: _FakePicker(selected: XFile.fromData(Uint8List(0))),
    );
    await expectLater(
      service.selectSingleImage(),
      throwsA(isA<ChatImageSelectionException>()),
    );
  });
}
