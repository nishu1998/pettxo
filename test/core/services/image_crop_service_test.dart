import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/services/image_crop_service.dart';

void main() {
  test('selectable Android post crop exposes only 1:1 and 4:5', () {
    final settings = socialPostAndroidCropSettings(
      ratio: ImageCropRatio.square,
      allowRatioSelection: true,
    );

    expect(settings.hideBottomControls, isFalse);
    expect(settings.lockAspectRatio, isTrue);
    expect(settings.initAspectRatio?.name, 'Square 1:1');
    expect(settings.aspectRatioPresets.map((preset) => preset.name), <String>[
      'Square 1:1',
      'Portrait 4:5',
    ]);
    expect(
      settings.aspectRatioPresets.map((preset) => preset.data),
      <(int, int)>[(1, 1), (4, 5)],
    );
  });

  test('locked Android post crop hides controls and keeps active ratio', () {
    final settings = socialPostAndroidCropSettings(
      ratio: ImageCropRatio.portraitFourByFive,
      allowRatioSelection: false,
    );

    expect(settings.hideBottomControls, isTrue);
    expect(settings.lockAspectRatio, isTrue);
    expect(settings.initAspectRatio?.name, 'Portrait 4:5');
  });
}
