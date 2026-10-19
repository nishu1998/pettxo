import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pettexo/core/services/image_crop_service.dart';
import 'package:pettexo/features/social/application/social_post_media_preparation_service.dart';
import 'package:pettexo/features/social/domain/models/social_post_model.dart';

void main() {
  late Directory root;
  late Directory managed;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('social-media-test-');
    managed = Directory('${root.path}/pettexo_social_prepared');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('gallery cancellation produces no prepared images', () async {
    final service = SocialPostMediaPreparationService(
      pickImages: () async => const <XFile>[],
      workingDirectory: managed,
    );

    final result = await service.pickCropAndPrepare(
      maxImages: 5,
      aspectRatio: SocialPostAspectRatio.square,
    );

    expect(result.galleryCancelled, isTrue);
    expect(result.images, isEmpty);
  });

  test('native post cropper exposes only square and portrait presets', () {
    expect(
      socialPostCropAspectRatioPresets.map((preset) => preset.name),
      <String>['Square 1:1', 'Portrait 4:5'],
    );
    expect(
      socialPostCropAspectRatioPresets.map((preset) => preset.data),
      <(int, int)>[(1, 1), (4, 5)],
    );
  });

  test(
    'first native crop chooses the shared ratio for following images',
    () async {
      final first = await _writeJpeg(root, 'first-source.jpg');
      final second = await _writeJpeg(root, 'second-source.jpg');
      final seenRatios = <ImageCropRatio>[];
      final selectionEnabled = <bool>[];
      var calls = 0;
      final service = SocialPostMediaPreparationService(
        cropPostImage: (source, initialRatio, allowRatioSelection) async {
          seenRatios.add(initialRatio);
          selectionEnabled.add(allowRatioSelection);
          final output = await _writeJpeg(root, 'selected-${calls++}.jpg');
          return CroppedPostMedia(
            croppedFile: output,
            selectedAspectRatio: calls == 1
                ? ImageCropRatio.portraitFourByFive
                : initialRatio,
          );
        },
        workingDirectory: managed,
      );

      final result = await service.preparePickedImages(
        picked: <XFile>[XFile(first.path), XFile(second.path)],
        maxImages: 5,
        aspectRatio: SocialPostAspectRatio.square,
        allowFirstCropRatioSelection: true,
        transactionalBatch: true,
      );

      expect(result.media, hasLength(2));
      expect(result.selectedAspectRatio, SocialPostAspectRatio.portrait);
      expect(selectionEnabled, <bool>[true, false]);
      expect(seenRatios, <ImageCropRatio>[
        ImageCropRatio.square,
        ImageCropRatio.portraitFourByFive,
      ]);
    },
  );

  test(
    'transactional initial selection rolls back on later cancellation',
    () async {
      final first = await _writeJpeg(root, 'first-source.jpg');
      final second = await _writeJpeg(root, 'second-source.jpg');
      var calls = 0;
      final service = SocialPostMediaPreparationService(
        cropPostImage: (_, ratio, allowRatioSelection) async {
          expect(allowRatioSelection, calls == 0);
          calls += 1;
          if (calls == 2) return null;
          return CroppedPostMedia(
            croppedFile: await _writeJpeg(root, 'first-crop.jpg'),
            selectedAspectRatio: ratio,
          );
        },
        workingDirectory: managed,
      );

      final result = await service.preparePickedImages(
        picked: <XFile>[XFile(first.path), XFile(second.path)],
        maxImages: 5,
        aspectRatio: SocialPostAspectRatio.square,
        allowFirstCropRatioSelection: true,
        transactionalBatch: true,
      );

      expect(result.media, isEmpty);
      expect(result.cropCancellationCount, 1);
      expect(await _managedFiles(managed), isEmpty);
      expect(await first.exists(), isTrue);
      expect(await second.exists(), isTrue);
    },
  );

  test(
    'Add Photos keeps the active ratio locked for every new image',
    () async {
      final source = await _writeJpeg(root, 'add-source.jpg');
      ImageCropRatio? seenRatio;
      bool? selectionEnabled;
      final service = SocialPostMediaPreparationService(
        pickImages: () async => <XFile>[XFile(source.path)],
        cropPostImage: (_, ratio, allowRatioSelection) async {
          seenRatio = ratio;
          selectionEnabled = allowRatioSelection;
          return CroppedPostMedia(
            croppedFile: await _writeJpeg(root, 'add-crop.jpg'),
            selectedAspectRatio: ratio,
          );
        },
        workingDirectory: managed,
      );

      final result = await service.pickCropAndPrepare(
        maxImages: 4,
        aspectRatio: SocialPostAspectRatio.portrait,
      );

      expect(result.media, hasLength(1));
      expect(seenRatio, ImageCropRatio.portraitFourByFive);
      expect(selectionEnabled, isFalse);
      expect(result.selectedAspectRatio, SocialPostAspectRatio.portrait);
    },
  );

  test('native crop cancellation is not reported as a failure', () async {
    final source = await _writeJpeg(root, 'source.jpg');
    final service = SocialPostMediaPreparationService(
      cropImage: (_, _) async => null,
      workingDirectory: managed,
    );

    final result = await service.preparePickedImages(
      picked: <XFile>[XFile(source.path)],
      maxImages: 5,
      aspectRatio: SocialPostAspectRatio.square,
    );

    expect(result.cropCancellationCount, 1);
    expect(result.failures, isEmpty);
    expect(await _managedFiles(managed), isEmpty);
  });

  for (final entry in <(String, int)>[
    ('7.2 MB', 7200000),
    ('just below 10 MiB', socialPostMaxUploadBytes - 1),
    ('exactly 10 MiB', socialPostMaxUploadBytes),
  ]) {
    test(
      'accepts valid cropped JPEG ${entry.$1} without recompression',
      () async {
        final source = await _writeJpeg(root, 'source.jpg');
        final cropped = await _writePaddedJpeg(root, 'crop.jpg', entry.$2);
        var optimizerCalled = false;
        final service = SocialPostMediaPreparationService(
          cropImage: (_, _) async => cropped,
          optimizeImage: (_) async {
            optimizerCalled = true;
            return null;
          },
          workingDirectory: managed,
        );

        final result = await service.preparePickedImages(
          picked: <XFile>[XFile(source.path)],
          maxImages: 5,
          aspectRatio: SocialPostAspectRatio.square,
        );

        expect(result.failures, isEmpty);
        expect(result.media, hasLength(1));
        expect(await result.images.single.length(), entry.$2);
        expect(optimizerCalled, isFalse);
        expect(result.media.single.source.path, isNot(source.path));
        expect(await source.exists(), isTrue);
      },
    );
  }

  test(
    'just-over-limit image is accepted after bounded optimization',
    () async {
      final source = await _writeJpeg(root, 'source.jpg');
      final cropped = await _writePaddedJpeg(
        root,
        'crop.jpg',
        socialPostMaxUploadBytes + 1,
      );
      final optimized = Uint8List.fromList(await source.readAsBytes());
      final service = SocialPostMediaPreparationService(
        cropImage: (_, _) async => cropped,
        optimizeImage: (_) async => optimized,
        workingDirectory: managed,
      );

      final result = await service.preparePickedImages(
        picked: <XFile>[XFile(source.path)],
        maxImages: 5,
        aspectRatio: SocialPostAspectRatio.square,
      );

      expect(result.optimizedCount, 1);
      expect(result.images, hasLength(1));
      expect(
        await result.images.single.length(),
        lessThan(socialPostMaxUploadBytes),
      );
    },
  );

  test('incompressible oversized image reports oversized category', () async {
    final source = await _writeJpeg(root, 'source.jpg');
    final cropped = await _writePaddedJpeg(
      root,
      'crop.jpg',
      socialPostMaxUploadBytes + 1,
    );
    final service = SocialPostMediaPreparationService(
      cropImage: (_, _) async => cropped,
      optimizeImage: (_) async => null,
      workingDirectory: managed,
    );

    final result = await service.preparePickedImages(
      picked: <XFile>[XFile(source.path)],
      maxImages: 5,
      aspectRatio: SocialPostAspectRatio.square,
    );

    expect(result.images, isEmpty);
    expect(
      result.failures.single.category,
      SocialPostMediaFailureCategory.oversizedAfterOptimization,
    );
  });

  test('corrupted JPEG reports unsupported format', () async {
    final source = await _writeJpeg(root, 'source.jpg');
    final corrupt = File('${root.path}/corrupt.jpg')
      ..writeAsBytesSync(<int>[0xff, 0xd8, 0xff, 1, 2, 3]);
    final service = SocialPostMediaPreparationService(
      cropImage: (_, _) async => corrupt,
      workingDirectory: managed,
    );

    final result = await service.preparePickedImages(
      picked: <XFile>[XFile(source.path)],
      maxImages: 1,
      aspectRatio: SocialPostAspectRatio.square,
    );

    expect(
      result.failures.single.category,
      SocialPostMediaFailureCategory.unsupportedFormat,
    );
  });

  for (final format in <String>[
    'png',
    'webp',
    'heic',
    'heif',
    'gif',
    'avif',
    'bmp',
  ]) {
    test(
      '$format picker source is retained through native crop and JPEG preparation',
      () async {
        final source = File('${root.path}/source.$format');
        await source.writeAsBytes(_encodedImage(format));
        final crop = await _writeJpeg(root, 'crop-$format.jpg');
        String? cropSourcePath;
        final service = SocialPostMediaPreparationService(
          cropImage: (managedSource, _) async {
            cropSourcePath = managedSource.path;
            expect(await File(managedSource.path).exists(), isTrue);
            return crop;
          },
          workingDirectory: managed,
        );

        final result = await service.preparePickedImages(
          picked: <XFile>[
            XFile(
              source.path,
              mimeType: 'image/$format',
              name: 'source.$format',
            ),
          ],
          maxImages: 1,
          aspectRatio: SocialPostAspectRatio.square,
        );

        expect(result.failures, isEmpty);
        expect(result.images, hasLength(1));
        expect(cropSourcePath, isNot(source.path));
        expect(result.media.single.sourceFormat, format);
      },
    );
  }

  test('transparent crop output is flattened onto white JPEG', () async {
    final source = await _writeJpeg(root, 'source.jpg');
    final transparent = img.Image(width: 32, height: 32, numChannels: 4);
    img.fill(transparent, color: img.ColorRgba8(0, 0, 0, 0));
    img.fillRect(
      transparent,
      x1: 8,
      y1: 8,
      x2: 23,
      y2: 23,
      color: img.ColorRgba8(220, 20, 20, 255),
    );
    final crop = File('${root.path}/transparent-crop.png');
    await crop.writeAsBytes(img.encodePng(transparent));
    final service = SocialPostMediaPreparationService(
      cropImage: (_, _) async => crop,
      workingDirectory: managed,
    );

    final result = await service.preparePickedImages(
      picked: <XFile>[XFile(source.path)],
      maxImages: 1,
      aspectRatio: SocialPostAspectRatio.square,
    );

    expect(result.failures, isEmpty);
    final bytes = await result.images.single.readAsBytes();
    expect(bytes.take(3), <int>[0xff, 0xd8, 0xff]);
    final decoded = img.decodeJpg(bytes)!;
    final corner = decoded.getPixel(0, 0);
    expect(corner.r, greaterThan(240));
    expect(corner.g, greaterThan(240));
    expect(corner.b, greaterThan(240));
    final center = decoded.getPixel(16, 16);
    expect(center.r, greaterThan(center.g + 100));
  });

  test('post cropper preserves alpha-capable source formats as PNG', () async {
    for (final extension in <String>['png', 'webp', 'gif', 'avif', 'bmp']) {
      expect(
        socialPostCropCompressFormatForSource(XFile('source.$extension')),
        ImageCompressFormat.png,
      );
    }
    expect(
      socialPostCropCompressFormatForSource(XFile('source.jpg')),
      ImageCompressFormat.jpg,
    );
    expect(
      socialPostCropCompressFormatForSource(
        XFile('picker-cache.jpg', mimeType: 'image/webp'),
      ),
      ImageCompressFormat.png,
    );
  });

  test('missing picker file reports unreadable source', () async {
    final service = SocialPostMediaPreparationService(
      cropImage: (_, _) async => fail('cropper must not run'),
      workingDirectory: managed,
    );
    final result = await service.preparePickedImages(
      picked: <XFile>[XFile('${root.path}/missing.jpg')],
      maxImages: 1,
      aspectRatio: SocialPostAspectRatio.square,
    );
    expect(
      result.failures.single.category,
      SocialPostMediaFailureCategory.unreadableSource,
    );
  });

  test(
    'unavailable managed directory reports temporary storage problem',
    () async {
      final source = await _writeJpeg(root, 'source.jpg');
      final directoryBlocker = File('${root.path}/not-a-directory');
      await directoryBlocker.writeAsString('occupied');
      final service = SocialPostMediaPreparationService(
        cropImage: (_, _) async => fail('cropper must not run'),
        workingDirectory: Directory(directoryBlocker.path),
      );

      final result = await service.preparePickedImages(
        picked: <XFile>[XFile(source.path)],
        maxImages: 1,
        aspectRatio: SocialPostAspectRatio.square,
      );

      expect(
        result.failures.single.category,
        SocialPostMediaFailureCategory.temporaryStorage,
      );
    },
  );

  test('native cropper exception preserves cause and stack', () async {
    final source = await _writeJpeg(root, 'source.jpg');
    final cause = StateError('native failure');
    final service = SocialPostMediaPreparationService(
      cropImage: (_, _) async => throw cause,
      workingDirectory: managed,
    );
    final result = await service.preparePickedImages(
      picked: <XFile>[XFile(source.path)],
      maxImages: 1,
      aspectRatio: SocialPostAspectRatio.square,
    );
    expect(
      result.failures.single.category,
      SocialPostMediaFailureCategory.cropperFailure,
    );
    expect(result.failures.single.cause, same(cause));
    expect(result.failures.single.stackTrace.toString(), isNotEmpty);
  });

  test(
    'optimizer exception reports compression failure and preserves cause',
    () async {
      final source = await _writeJpeg(root, 'source.jpg');
      final crop = await _writePaddedJpeg(
        root,
        'crop.jpg',
        socialPostMaxUploadBytes + 1,
      );
      final cause = StateError('compressor stopped');
      final service = SocialPostMediaPreparationService(
        cropImage: (_, _) async => crop,
        optimizeImage: (_) async => throw cause,
        workingDirectory: managed,
      );
      final result = await service.preparePickedImages(
        picked: <XFile>[XFile(source.path)],
        maxImages: 1,
        aspectRatio: SocialPostAspectRatio.square,
      );
      expect(
        result.failures.single.category,
        SocialPostMediaFailureCategory.compressionFailure,
      );
      expect(result.failures.single.cause, same(cause));
    },
  );

  test(
    'successful recrop uses original source and replaces all outputs',
    () async {
      final media = await _prepareTwoMedia(root, managed);
      final oldOutputs = media.map((item) => item.prepared.path).toList();
      final sourcePaths = media.map((item) => item.source.path).toList();
      final seenSources = <String>[];
      var cropIndex = 0;
      final service = SocialPostMediaPreparationService(
        cropImage: (source, ratio) async {
          expect(ratio, ImageCropRatio.portraitFourByFive);
          seenSources.add(source.path);
          return _writeJpeg(root, 'recrop-${cropIndex++}.jpg');
        },
        workingDirectory: managed,
      );

      final result = await service.recropPreparedMedia(
        current: media,
        aspectRatio: SocialPostAspectRatio.portrait,
      );

      expect(result.succeeded, isTrue);
      expect(seenSources, sourcePaths);
      expect(result.media.map((item) => item.source.path), sourcePaths);
      for (final path in oldOutputs) {
        expect(await File(path).exists(), isFalse);
      }
    },
  );

  test(
    'cancel midway rolls back every image and deletes attempt outputs',
    () async {
      final media = await _prepareTwoMedia(root, managed);
      final before = (await _managedFiles(managed)).toSet();
      var calls = 0;
      final service = SocialPostMediaPreparationService(
        cropImage: (_, _) async {
          calls += 1;
          return calls == 1 ? _writeJpeg(root, 'attempt.jpg') : null;
        },
        workingDirectory: managed,
      );

      final result = await service.recropPreparedMedia(
        current: media,
        aspectRatio: SocialPostAspectRatio.portrait,
      );

      expect(result.cancelled, isTrue);
      expect(result.media, media);
      expect((await _managedFiles(managed)).toSet(), before);
      for (final item in media) {
        expect(await File(item.prepared.path).exists(), isTrue);
        expect(await File(item.source.path).exists(), isTrue);
      }
    },
  );

  test('failure midway rolls back earlier replacement', () async {
    final media = await _prepareTwoMedia(root, managed);
    final before = (await _managedFiles(managed)).toSet();
    var calls = 0;
    final service = SocialPostMediaPreparationService(
      cropImage: (_, _) async {
        calls += 1;
        if (calls == 2) throw StateError('second crop failed');
        return _writeJpeg(root, 'attempt.jpg');
      },
      workingDirectory: managed,
    );

    final result = await service.recropPreparedMedia(
      current: media,
      aspectRatio: SocialPostAspectRatio.portrait,
    );

    expect(
      result.failure?.category,
      SocialPostMediaFailureCategory.cropperFailure,
    );
    expect((await _managedFiles(managed)).toSet(), before);
  });

  test(
    'switching back always crops the retained original, not prior output',
    () async {
      final media = await _prepareTwoMedia(root, managed);
      final originalSources = media.map((item) => item.source.path).toList();
      final seen = <String>[];
      var cropIndex = 0;
      final service = SocialPostMediaPreparationService(
        cropImage: (source, _) async {
          seen.add(source.path);
          return _writeJpeg(root, 'switch-${cropIndex++}.jpg');
        },
        workingDirectory: managed,
      );
      final portrait = await service.recropPreparedMedia(
        current: media,
        aspectRatio: SocialPostAspectRatio.portrait,
      );
      final square = await service.recropPreparedMedia(
        current: portrait.media,
        aspectRatio: SocialPostAspectRatio.square,
      );

      expect(square.succeeded, isTrue);
      expect(seen, <String>[...originalSources, ...originalSources]);
    },
  );
}

Future<List<SocialPostPreparedMedia>> _prepareTwoMedia(
  Directory root,
  Directory managed,
) async {
  final first = await _writeJpeg(root, 'first.jpg', red: 255);
  final second = await _writeJpeg(root, 'second.jpg', blue: 255);
  var cropIndex = 0;
  final service = SocialPostMediaPreparationService(
    cropImage: (_, _) => _writeJpeg(root, 'initial-${cropIndex++}.jpg'),
    workingDirectory: managed,
  );
  final result = await service.preparePickedImages(
    picked: <XFile>[XFile(first.path), XFile(second.path)],
    maxImages: 2,
    aspectRatio: SocialPostAspectRatio.square,
  );
  expect(result.failures, isEmpty);
  return result.media;
}

Future<List<String>> _managedFiles(Directory directory) async {
  if (!await directory.exists()) return const <String>[];
  return directory
      .listSync()
      .whereType<File>()
      .map((file) => file.path)
      .toList(growable: false);
}

List<int> _encodedImage(String format) {
  final image = img.Image(width: 4, height: 4);
  img.fill(image, color: img.ColorRgb8(20, 40, 60));
  return switch (format) {
    'png' => img.encodePng(image),
    'webp' => <int>[...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits],
    'heic' ||
    'heif' => <int>[0, 0, 0, 24, ...'ftyp'.codeUnits, ...'heic'.codeUnits],
    'gif' => img.encodeGif(image),
    'avif' => <int>[0, 0, 0, 24, ...'ftyp'.codeUnits, ...'avif'.codeUnits],
    'bmp' => img.encodeBmp(image),
    _ => throw ArgumentError.value(format),
  };
}

Future<File> _writeJpeg(
  Directory directory,
  String name, {
  int red = 40,
  int blue = 40,
}) async {
  final image = img.Image(width: 4, height: 4);
  img.fill(image, color: img.ColorRgb8(red, 20, blue));
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(img.encodeJpg(image, quality: 95));
  return file;
}

Future<File> _writePaddedJpeg(
  Directory directory,
  String name,
  int byteLength,
) async {
  final base = await _writeJpeg(directory, '$name.base');
  final bytes = await base.readAsBytes();
  final padded = Uint8List(byteLength)..setRange(0, bytes.length, bytes);
  final file = File('${directory.path}/$name');
  await file.writeAsBytes(padded);
  return file;
}
