import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../../core/services/image_crop_service.dart';
import '../domain/models/social_post_model.dart';

const int socialPostMaxUploadBytes = 10 * 1024 * 1024;

typedef SocialPostImagePicker = Future<List<XFile>> Function();
typedef SocialPostImageCropper =
    Future<File?> Function(XFile source, ImageCropRatio ratio);
typedef SocialPostImageOptimizer = Future<Uint8List?> Function(Uint8List bytes);

@immutable
class SocialPostMediaPreparationResult {
  const SocialPostMediaPreparationResult({
    required this.images,
    required this.galleryCancelled,
    required this.cropCancellationCount,
    required this.failureCount,
    required this.oversizedFailureCount,
    required this.optimizedCount,
    required this.selectionTruncated,
  });

  final List<XFile> images;
  final bool galleryCancelled;
  final int cropCancellationCount;
  final int failureCount;
  final int oversizedFailureCount;
  final int optimizedCount;
  final bool selectionTruncated;
}

class SocialPostMediaPreparationService {
  SocialPostMediaPreparationService({
    ImagePicker? picker,
    ImageCropService? cropService,
    SocialPostImagePicker? pickImages,
    SocialPostImageCropper? cropImage,
    SocialPostImageOptimizer? optimizeImage,
    Directory? workingDirectory,
  }) : _picker = picker ?? ImagePicker(),
       _cropService = cropService ?? ImageCropService(),
       _pickImagesOverride = pickImages,
       _cropImageOverride = cropImage,
       _optimizeImageOverride = optimizeImage,
       _workingDirectory = workingDirectory;

  final ImagePicker _picker;
  final ImageCropService _cropService;
  final SocialPostImagePicker? _pickImagesOverride;
  final SocialPostImageCropper? _cropImageOverride;
  final SocialPostImageOptimizer? _optimizeImageOverride;
  final Directory? _workingDirectory;

  static int _fileCounter = 0;

  Future<SocialPostMediaPreparationResult> pickCropAndPrepare({
    required int maxImages,
    required SocialPostAspectRatio aspectRatio,
  }) async {
    if (maxImages <= 0) {
      return const SocialPostMediaPreparationResult(
        images: <XFile>[],
        galleryCancelled: false,
        cropCancellationCount: 0,
        failureCount: 0,
        oversizedFailureCount: 0,
        optimizedCount: 0,
        selectionTruncated: false,
      );
    }

    final picked = await pickGalleryImages();
    if (picked.isEmpty) {
      return const SocialPostMediaPreparationResult(
        images: <XFile>[],
        galleryCancelled: true,
        cropCancellationCount: 0,
        failureCount: 0,
        oversizedFailureCount: 0,
        optimizedCount: 0,
        selectionTruncated: false,
      );
    }

    return preparePickedImages(
      picked: picked,
      maxImages: maxImages,
      aspectRatio: aspectRatio,
    );
  }

  Future<List<XFile>> pickGalleryImages() =>
      _pickImagesOverride?.call() ?? _picker.pickMultiImage(imageQuality: 100);

  Future<SocialPostMediaPreparationResult> preparePickedImages({
    required List<XFile> picked,
    required int maxImages,
    required SocialPostAspectRatio aspectRatio,
  }) async {
    if (picked.isEmpty || maxImages <= 0) {
      return const SocialPostMediaPreparationResult(
        images: <XFile>[],
        galleryCancelled: true,
        cropCancellationCount: 0,
        failureCount: 0,
        oversizedFailureCount: 0,
        optimizedCount: 0,
        selectionTruncated: false,
      );
    }

    final prepared = <XFile>[];
    var cropCancellationCount = 0;
    var failureCount = 0;
    var oversizedFailureCount = 0;
    var optimizedCount = 0;

    for (final source in picked.take(maxImages)) {
      File? cropped;
      try {
        // Reading once before invoking the cropper catches expired Android
        // provider/cache handles while the picker is still in the foreground.
        final sourceBytes = await source.readAsBytes();
        if (sourceBytes.isEmpty) {
          failureCount += 1;
          continue;
        }

        cropped =
            await (_cropImageOverride?.call(source, _cropRatio(aspectRatio)) ??
                _cropService.cropImage(
                  source: source,
                  context: ImageCropContext.post,
                  ratio: _cropRatio(aspectRatio),
                ));
        if (cropped == null) {
          if (_cropImageOverride == null && _cropService.hadLastError) {
            failureCount += 1;
          } else {
            cropCancellationCount += 1;
          }
          continue;
        }

        final croppedBytes = await cropped.readAsBytes();
        final preparedBytes = await _prepareCroppedJpeg(croppedBytes);
        if (preparedBytes == null) {
          failureCount += 1;
          if (croppedBytes.length > socialPostMaxUploadBytes) {
            oversizedFailureCount += 1;
          }
          continue;
        }
        if (croppedBytes.length > socialPostMaxUploadBytes) {
          optimizedCount += 1;
        }

        final output = await _writeManagedCopy(preparedBytes);
        prepared.add(XFile(output.path, mimeType: 'image/jpeg'));
      } catch (_) {
        failureCount += 1;
      } finally {
        if (cropped != null && cropped.path != source.path) {
          await _deleteIfPresent(cropped);
        }
      }
    }

    return SocialPostMediaPreparationResult(
      images: List<XFile>.unmodifiable(prepared),
      galleryCancelled: false,
      cropCancellationCount: cropCancellationCount,
      failureCount: failureCount,
      oversizedFailureCount: oversizedFailureCount,
      optimizedCount: optimizedCount,
      selectionTruncated: picked.length > maxImages,
    );
  }

  Future<Uint8List?> _prepareCroppedJpeg(Uint8List bytes) async {
    final isReadableJpeg = await compute(_isReadableJpeg, bytes);
    if (!isReadableJpeg) return null;
    if (bytes.length <= socialPostMaxUploadBytes) return bytes;

    final optimized =
        await (_optimizeImageOverride?.call(bytes) ??
            compute(_optimizeSocialPostJpeg, bytes));
    if (optimized == null || optimized.isEmpty) return null;
    if (optimized.length > socialPostMaxUploadBytes) return null;
    return await compute(_isReadableJpeg, optimized) ? optimized : null;
  }

  Future<File> _writeManagedCopy(Uint8List bytes) async {
    final directory =
        _workingDirectory ??
        Directory('${Directory.systemTemp.path}/pettexo_social_prepared');
    await directory.create(recursive: true);
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_fileCounter++}';
    final file = File('${directory.path}/post_$id.jpg');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> deletePreparedImages(Iterable<XFile> images) async {
    for (final image in images) {
      final file = File(image.path);
      if (!file.path.contains('pettexo_social_prepared')) continue;
      await _deleteIfPresent(file);
    }
  }

  static Future<void> deletePreparedPaths(Iterable<String> paths) =>
      deletePreparedImages(paths.map(XFile.new));

  static Future<void> _deleteIfPresent(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup must not replace the actual preparation result.
    }
  }

  static ImageCropRatio _cropRatio(SocialPostAspectRatio ratio) =>
      switch (ratio) {
        SocialPostAspectRatio.square => ImageCropRatio.square,
        SocialPostAspectRatio.portrait => ImageCropRatio.portraitFourByFive,
        SocialPostAspectRatio.landscape => ImageCropRatio.square,
      };
}

bool _isReadableJpeg(Uint8List bytes) {
  if (bytes.length < 3 ||
      bytes[0] != 0xff ||
      bytes[1] != 0xd8 ||
      bytes[2] != 0xff) {
    return false;
  }
  return img.decodeImage(bytes) != null;
}

Uint8List? _optimizeSocialPostJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var oriented = img.bakeOrientation(decoded);
  const attempts = <(int, int)>[
    (3200, 92),
    (2560, 88),
    (2048, 84),
    (1600, 80),
    (1280, 76),
  ];
  for (final (maxDimension, quality) in attempts) {
    final longest = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;
    final candidate = longest > maxDimension
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? maxDimension : null,
            height: oriented.height > oriented.width ? maxDimension : null,
          )
        : oriented;
    final encoded = Uint8List.fromList(
      img.encodeJpg(candidate, quality: quality),
    );
    if (encoded.length <= socialPostMaxUploadBytes) return encoded;
    oriented = candidate;
  }
  return null;
}
