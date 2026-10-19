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
typedef SocialPostSelectableImageCropper =
    Future<CroppedPostMedia?> Function(
      XFile source,
      ImageCropRatio initialRatio,
      bool allowRatioSelection,
    );
typedef SocialPostImageOptimizer = Future<Uint8List?> Function(Uint8List bytes);

enum SocialPostMediaPreparationStage { idle, copying, cropping, processing }

typedef SocialPostMediaPreparationStageChanged =
    void Function(SocialPostMediaPreparationStage stage);

enum SocialPostMediaFailureCategory {
  unreadableSource,
  unsupportedFormat,
  cropperFailure,
  temporaryStorage,
  oversizedAfterOptimization,
  compressionFailure,
  unexpected,
}

@immutable
class SocialPostMediaPreparationException implements Exception {
  const SocialPostMediaPreparationException({
    required this.category,
    required this.stage,
    required this.sourceFormat,
    required this.cause,
    required this.stackTrace,
    this.safeByteSize,
    this.outputExists,
  });

  final SocialPostMediaFailureCategory category;
  final String stage;
  final String sourceFormat;
  final Object cause;
  final StackTrace stackTrace;
  final int? safeByteSize;
  final bool? outputExists;

  String get userMessage => switch (category) {
    SocialPostMediaFailureCategory.oversizedAfterOptimization =>
      'This photo is too large to upload. The maximum size is 10 MB, even '
          'after compression. Please choose a smaller photo.',
    SocialPostMediaFailureCategory.unsupportedFormat =>
      "This photo format couldn't be processed. Please choose a JPEG or "
          'another supported photo.',
    SocialPostMediaFailureCategory.unreadableSource =>
      "We couldn't open this photo. Please select it again.",
    SocialPostMediaFailureCategory.cropperFailure =>
      "We couldn't crop this photo. Please try again.",
    SocialPostMediaFailureCategory.temporaryStorage =>
      "We couldn't prepare this photo because temporary storage is "
          'unavailable. Please free up space and try again.',
    SocialPostMediaFailureCategory.compressionFailure =>
      "We couldn't compress this photo. Please choose another photo or try "
          'again.',
    SocialPostMediaFailureCategory.unexpected =>
      'Something went wrong while preparing this photo. Please try again.',
  };

  @override
  String toString() => 'SocialPostMediaPreparationException($category, $stage)';
}

@immutable
class SocialPostPreparedMedia {
  const SocialPostPreparedMedia({
    required this.source,
    required this.prepared,
    required this.sourceFormat,
  });

  final XFile source;
  final XFile prepared;
  final String sourceFormat;
}

@immutable
class SocialPostMediaPreparationResult {
  const SocialPostMediaPreparationResult({
    this.media = const <SocialPostPreparedMedia>[],
    List<XFile>? images,
    required this.galleryCancelled,
    required this.cropCancellationCount,
    int? failureCount,
    int? oversizedFailureCount,
    required this.optimizedCount,
    required this.selectionTruncated,
    this.selectedAspectRatio,
    this.failures = const <SocialPostMediaPreparationException>[],
  }) : _legacyImages = images ?? const <XFile>[],
       _legacyFailureCount = failureCount,
       _legacyOversizedFailureCount = oversizedFailureCount;

  final List<SocialPostPreparedMedia> media;
  final List<XFile> _legacyImages;
  final bool galleryCancelled;
  final int cropCancellationCount;
  final int? _legacyFailureCount;
  final int? _legacyOversizedFailureCount;
  final int optimizedCount;
  final bool selectionTruncated;
  final SocialPostAspectRatio? selectedAspectRatio;
  final List<SocialPostMediaPreparationException> failures;

  List<XFile> get images => media.isEmpty
      ? _legacyImages
      : media.map((item) => item.prepared).toList(growable: false);
  int get failureCount => _legacyFailureCount ?? failures.length;
  int get oversizedFailureCount =>
      _legacyOversizedFailureCount ??
      failures
          .where(
            (failure) =>
                failure.category ==
                SocialPostMediaFailureCategory.oversizedAfterOptimization,
          )
          .length;
}

@immutable
class SocialPostMediaRecropResult {
  const SocialPostMediaRecropResult._({
    required this.media,
    required this.cancelled,
    this.failure,
  });

  factory SocialPostMediaRecropResult.success(
    List<SocialPostPreparedMedia> media,
  ) => SocialPostMediaRecropResult._(
    media: List<SocialPostPreparedMedia>.unmodifiable(media),
    cancelled: false,
  );

  factory SocialPostMediaRecropResult.cancelled(
    List<SocialPostPreparedMedia> original,
  ) => SocialPostMediaRecropResult._(
    media: List<SocialPostPreparedMedia>.unmodifiable(original),
    cancelled: true,
  );

  factory SocialPostMediaRecropResult.failure(
    List<SocialPostPreparedMedia> original,
    SocialPostMediaPreparationException failure,
  ) => SocialPostMediaRecropResult._(
    media: List<SocialPostPreparedMedia>.unmodifiable(original),
    cancelled: false,
    failure: failure,
  );

  final List<SocialPostPreparedMedia> media;
  final bool cancelled;
  final SocialPostMediaPreparationException? failure;
  bool get succeeded => !cancelled && failure == null;
}

class SocialPostMediaPreparationService {
  SocialPostMediaPreparationService({
    ImagePicker? picker,
    ImageCropService? cropService,
    SocialPostImagePicker? pickImages,
    SocialPostImageCropper? cropImage,
    SocialPostSelectableImageCropper? cropPostImage,
    SocialPostImageOptimizer? optimizeImage,
    Directory? workingDirectory,
  }) : _picker = picker ?? ImagePicker(),
       _cropService = cropService ?? ImageCropService(),
       _pickImagesOverride = pickImages,
       _cropImageOverride = cropImage,
       _cropPostImageOverride = cropPostImage,
       _optimizeImageOverride = optimizeImage,
       _workingDirectory = workingDirectory;

  final ImagePicker _picker;
  final ImageCropService _cropService;
  final SocialPostImagePicker? _pickImagesOverride;
  final SocialPostImageCropper? _cropImageOverride;
  final SocialPostSelectableImageCropper? _cropPostImageOverride;
  final SocialPostImageOptimizer? _optimizeImageOverride;
  final Directory? _workingDirectory;

  static int _fileCounter = 0;

  Future<SocialPostMediaPreparationResult> pickCropAndPrepare({
    required int maxImages,
    required SocialPostAspectRatio aspectRatio,
    SocialPostMediaPreparationStageChanged? onStageChanged,
  }) async {
    if (maxImages <= 0) return _emptyResult();
    final picked = await pickGalleryImages();
    if (picked.isEmpty) return _emptyResult(galleryCancelled: true);
    return preparePickedImages(
      picked: picked,
      maxImages: maxImages,
      aspectRatio: aspectRatio,
      transactionalBatch: true,
      onStageChanged: onStageChanged,
    );
  }

  Future<List<XFile>> pickGalleryImages() =>
      _pickImagesOverride?.call() ?? _picker.pickMultiImage(imageQuality: 100);

  Future<SocialPostMediaPreparationResult> preparePickedImages({
    required List<XFile> picked,
    required int maxImages,
    required SocialPostAspectRatio aspectRatio,
    bool allowFirstCropRatioSelection = false,
    bool transactionalBatch = false,
    SocialPostMediaPreparationStageChanged? onStageChanged,
  }) async {
    if (picked.isEmpty || maxImages <= 0) {
      return _emptyResult(galleryCancelled: picked.isEmpty);
    }

    final prepared = <SocialPostPreparedMedia>[];
    final failures = <SocialPostMediaPreparationException>[];
    var cropCancellationCount = 0;
    var optimizedCount = 0;
    var selectedAspectRatio = aspectRatio;

    var index = 0;
    for (final selected in picked.take(maxImages)) {
      XFile? sourceCopy;
      try {
        onStageChanged?.call(SocialPostMediaPreparationStage.copying);
        sourceCopy = await _createManagedSourceCopy(selected);
        final outcome = await _cropAndPrepareSource(
          sourceCopy,
          aspectRatio: selectedAspectRatio,
          sourceFormat: _safeSourceFormat(selected),
          allowRatioSelection: allowFirstCropRatioSelection && index == 0,
          onStageChanged: onStageChanged,
        );
        if (outcome == null) {
          cropCancellationCount += 1;
          await deletePreparedImages(<XFile>[sourceCopy]);
          if (transactionalBatch) {
            await deletePreparedMedia(prepared);
            onStageChanged?.call(SocialPostMediaPreparationStage.idle);
            return SocialPostMediaPreparationResult(
              galleryCancelled: false,
              cropCancellationCount: cropCancellationCount,
              optimizedCount: optimizedCount,
              selectionTruncated: picked.length > maxImages,
              selectedAspectRatio: selectedAspectRatio,
            );
          }
          index += 1;
          continue;
        }
        prepared.add(outcome.media);
        selectedAspectRatio = outcome.selectedAspectRatio;
        if (outcome.optimized) optimizedCount += 1;
      } on SocialPostMediaPreparationException catch (failure) {
        failures.add(failure);
        _debugFailure(failure);
        if (sourceCopy != null) {
          await deletePreparedImages(<XFile>[sourceCopy]);
        }
        if (transactionalBatch) {
          await deletePreparedMedia(prepared);
          prepared.clear();
          break;
        }
      } catch (error, stackTrace) {
        final failure = _failure(
          SocialPostMediaFailureCategory.unexpected,
          stage: 'prepare-selected-source',
          sourceFormat: _safeSourceFormat(selected),
          cause: error,
          stackTrace: stackTrace,
        );
        failures.add(failure);
        _debugFailure(failure);
        if (sourceCopy != null) {
          await deletePreparedImages(<XFile>[sourceCopy]);
        }
        if (transactionalBatch) {
          await deletePreparedMedia(prepared);
          prepared.clear();
          break;
        }
      }
      index += 1;
    }

    onStageChanged?.call(SocialPostMediaPreparationStage.idle);
    return SocialPostMediaPreparationResult(
      media: List<SocialPostPreparedMedia>.unmodifiable(prepared),
      galleryCancelled: false,
      cropCancellationCount: cropCancellationCount,
      optimizedCount: optimizedCount,
      selectionTruncated: picked.length > maxImages,
      selectedAspectRatio: selectedAspectRatio,
      failures: List<SocialPostMediaPreparationException>.unmodifiable(
        failures,
      ),
    );
  }

  Future<SocialPostMediaRecropResult> recropPreparedMedia({
    required List<SocialPostPreparedMedia> current,
    required SocialPostAspectRatio aspectRatio,
    SocialPostMediaPreparationStageChanged? onStageChanged,
  }) async {
    final replacements = <SocialPostPreparedMedia>[];
    for (final existing in current) {
      try {
        final outcome = await _cropAndPrepareSource(
          existing.source,
          aspectRatio: aspectRatio,
          sourceFormat: existing.sourceFormat,
          onStageChanged: onStageChanged,
        );
        if (outcome == null) {
          await _deletePreparedOutputs(replacements);
          onStageChanged?.call(SocialPostMediaPreparationStage.idle);
          return SocialPostMediaRecropResult.cancelled(current);
        }
        replacements.add(outcome.media);
      } on SocialPostMediaPreparationException catch (failure) {
        _debugFailure(failure);
        await _deletePreparedOutputs(replacements);
        onStageChanged?.call(SocialPostMediaPreparationStage.idle);
        return SocialPostMediaRecropResult.failure(current, failure);
      } catch (error, stackTrace) {
        final failure = _failure(
          SocialPostMediaFailureCategory.unexpected,
          stage: 'recrop-source',
          sourceFormat: existing.sourceFormat,
          cause: error,
          stackTrace: stackTrace,
        );
        _debugFailure(failure);
        await _deletePreparedOutputs(replacements);
        onStageChanged?.call(SocialPostMediaPreparationStage.idle);
        return SocialPostMediaRecropResult.failure(current, failure);
      }
    }

    await _deletePreparedOutputs(current);
    onStageChanged?.call(SocialPostMediaPreparationStage.idle);
    return SocialPostMediaRecropResult.success(replacements);
  }

  Future<XFile> _createManagedSourceCopy(XFile selected) async {
    final format = _safeSourceFormat(selected);
    Uint8List bytes;
    try {
      bytes = await selected.readAsBytes();
      if (bytes.isEmpty) throw const FileSystemException('Empty image');
    } catch (error, stackTrace) {
      throw _failure(
        SocialPostMediaFailureCategory.unreadableSource,
        stage: 'read-picker-source',
        sourceFormat: format,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    try {
      final extension = _safeSourceExtension(selected, bytes);
      final file = await _writeManagedCopy(
        bytes,
        prefix: 'source',
        extension: extension,
      );
      return XFile(file.path, mimeType: selected.mimeType);
    } catch (error, stackTrace) {
      throw _failure(
        SocialPostMediaFailureCategory.temporaryStorage,
        stage: 'copy-picker-source',
        sourceFormat: format,
        cause: error,
        stackTrace: stackTrace,
        safeByteSize: bytes.length,
      );
    }
  }

  Future<_PreparedOutcome?> _cropAndPrepareSource(
    XFile source, {
    required SocialPostAspectRatio aspectRatio,
    required String sourceFormat,
    bool allowRatioSelection = false,
    SocialPostMediaPreparationStageChanged? onStageChanged,
  }) async {
    File? cropped;
    var selectedAspectRatio = aspectRatio;
    int? sourceByteSize;
    try {
      sourceByteSize = await source.length();
    } catch (_) {
      // The typed read/crop failure below remains the primary diagnostic.
    }
    try {
      try {
        onStageChanged?.call(SocialPostMediaPreparationStage.cropping);
        final initialRatio = _cropRatio(aspectRatio);
        final cropResult = _cropPostImageOverride != null
            ? await _cropPostImageOverride(
                source,
                initialRatio,
                allowRatioSelection,
              )
            : _cropImageOverride != null
            ? await _legacyCropResult(source, initialRatio)
            : await _cropService.cropPostImage(
                source: source,
                initialRatio: initialRatio,
                allowRatioSelection: allowRatioSelection,
              );
        cropped = cropResult?.croppedFile;
        onStageChanged?.call(SocialPostMediaPreparationStage.processing);
        selectedAspectRatio = cropResult == null
            ? aspectRatio
            : _socialAspectRatio(cropResult.selectedAspectRatio);
      } catch (error, stackTrace) {
        throw _failure(
          SocialPostMediaFailureCategory.cropperFailure,
          stage: 'native-cropper',
          sourceFormat: sourceFormat,
          cause: error,
          stackTrace: stackTrace,
          safeByteSize: sourceByteSize,
        );
      }
      if (cropped == null) {
        if (_cropImageOverride == null &&
            _cropPostImageOverride == null &&
            _cropService.hadLastError) {
          throw _failure(
            SocialPostMediaFailureCategory.cropperFailure,
            stage: 'native-cropper',
            sourceFormat: sourceFormat,
            cause: _cropService.lastError ?? StateError('Cropper failed'),
            stackTrace: _cropService.lastStackTrace ?? StackTrace.current,
            safeByteSize: sourceByteSize,
          );
        }
        return null;
      }

      Uint8List croppedBytes;
      try {
        if (!await cropped.exists()) {
          throw const FileSystemException('Crop output does not exist');
        }
        croppedBytes = await cropped.readAsBytes();
        if (croppedBytes.isEmpty) {
          throw const FileSystemException('Crop output is empty');
        }
      } catch (error, stackTrace) {
        throw _failure(
          SocialPostMediaFailureCategory.temporaryStorage,
          stage: 'read-crop-output',
          sourceFormat: sourceFormat,
          cause: error,
          stackTrace: stackTrace,
          outputExists: await cropped.exists(),
        );
      }

      final output = await _prepareCropBytes(
        croppedBytes,
        sourceFormat: sourceFormat,
      );
      File managed;
      try {
        managed = await _writeManagedCopy(
          output.bytes,
          prefix: 'prepared',
          extension: 'jpg',
        );
      } catch (error, stackTrace) {
        throw _failure(
          SocialPostMediaFailureCategory.temporaryStorage,
          stage: 'write-prepared-output',
          sourceFormat: sourceFormat,
          cause: error,
          stackTrace: stackTrace,
          safeByteSize: output.bytes.length,
        );
      }
      return _PreparedOutcome(
        media: SocialPostPreparedMedia(
          source: source,
          prepared: XFile(managed.path, mimeType: 'image/jpeg'),
          sourceFormat: sourceFormat,
        ),
        optimized: output.optimized,
        selectedAspectRatio: selectedAspectRatio,
      );
    } finally {
      if (cropped != null && cropped.path != source.path) {
        await _deleteIfPresent(cropped);
      }
    }
  }

  Future<_PreparedBytes> _prepareCropBytes(
    Uint8List bytes, {
    required String sourceFormat,
  }) async {
    final detected = _detectImageFormat(bytes);
    if (detected == 'jpeg') {
      final readable = await compute(_isReadableImage, bytes);
      if (!readable) {
        throw _failure(
          SocialPostMediaFailureCategory.unsupportedFormat,
          stage: 'validate-crop-output',
          sourceFormat: sourceFormat,
          cause: const FormatException('Invalid JPEG crop output'),
          stackTrace: StackTrace.current,
          safeByteSize: bytes.length,
        );
      }
      if (bytes.length <= socialPostMaxUploadBytes) {
        return _PreparedBytes(bytes, optimized: false);
      }
    } else {
      final readable = await compute(_isReadableImage, bytes);
      if (!readable) {
        throw _failure(
          SocialPostMediaFailureCategory.unsupportedFormat,
          stage: 'validate-crop-output',
          sourceFormat: sourceFormat,
          cause: FormatException('Unsupported crop output: $detected'),
          stackTrace: StackTrace.current,
          safeByteSize: bytes.length,
        );
      }
    }

    Uint8List? optimized;
    try {
      optimized =
          await (_optimizeImageOverride?.call(bytes) ??
              compute(_optimizeSocialPostImage, bytes));
    } catch (error, stackTrace) {
      throw _failure(
        SocialPostMediaFailureCategory.compressionFailure,
        stage: 'optimize-crop-output',
        sourceFormat: sourceFormat,
        cause: error,
        stackTrace: stackTrace,
        safeByteSize: bytes.length,
      );
    }
    if (optimized == null || optimized.isEmpty) {
      final category = bytes.length > socialPostMaxUploadBytes
          ? SocialPostMediaFailureCategory.oversizedAfterOptimization
          : SocialPostMediaFailureCategory.compressionFailure;
      throw _failure(
        category,
        stage: 'optimize-crop-output',
        sourceFormat: sourceFormat,
        cause: StateError('Image optimizer produced no usable output'),
        stackTrace: StackTrace.current,
        safeByteSize: bytes.length,
      );
    }
    if (optimized.length > socialPostMaxUploadBytes) {
      throw _failure(
        SocialPostMediaFailureCategory.oversizedAfterOptimization,
        stage: 'validate-optimized-output',
        sourceFormat: sourceFormat,
        cause: StateError('Optimized image exceeds upload limit'),
        stackTrace: StackTrace.current,
        safeByteSize: optimized.length,
      );
    }
    if (!await compute(_isReadableJpeg, optimized)) {
      throw _failure(
        SocialPostMediaFailureCategory.compressionFailure,
        stage: 'validate-optimized-output',
        sourceFormat: sourceFormat,
        cause: const FormatException('Optimizer did not produce JPEG'),
        stackTrace: StackTrace.current,
        safeByteSize: optimized.length,
      );
    }
    return _PreparedBytes(optimized, optimized: true);
  }

  Future<File> _writeManagedCopy(
    Uint8List bytes, {
    required String prefix,
    required String extension,
  }) async {
    final directory =
        _workingDirectory ??
        Directory('${Directory.systemTemp.path}/pettexo_social_prepared');
    await directory.create(recursive: true);
    final id = '${DateTime.now().microsecondsSinceEpoch}_${_fileCounter++}';
    final file = File('${directory.path}/${prefix}_$id.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> deletePreparedMedia(
    Iterable<SocialPostPreparedMedia> media,
  ) async {
    for (final item in media) {
      await deletePreparedImages(<XFile>[item.prepared, item.source]);
    }
  }

  static Future<void> _deletePreparedOutputs(
    Iterable<SocialPostPreparedMedia> media,
  ) => deletePreparedImages(
    media
        .where((item) => item.prepared.path != item.source.path)
        .map((item) => item.prepared),
  );

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
      // Cleanup is best-effort and must never replace the primary result.
    }
  }

  static SocialPostMediaPreparationResult _emptyResult({
    bool galleryCancelled = false,
  }) => SocialPostMediaPreparationResult(
    galleryCancelled: galleryCancelled,
    cropCancellationCount: 0,
    optimizedCount: 0,
    selectionTruncated: false,
  );

  static SocialPostMediaPreparationException _failure(
    SocialPostMediaFailureCategory category, {
    required String stage,
    required String sourceFormat,
    required Object cause,
    required StackTrace stackTrace,
    int? safeByteSize,
    bool? outputExists,
  }) => SocialPostMediaPreparationException(
    category: category,
    stage: stage,
    sourceFormat: sourceFormat,
    cause: cause,
    stackTrace: stackTrace,
    safeByteSize: safeByteSize,
    outputExists: outputExists,
  );

  static void _debugFailure(SocialPostMediaPreparationException failure) {
    if (!kDebugMode) return;
    debugPrint(
      'SocialPostMediaPreparation failed: stage=${failure.stage}, '
      'format=${failure.sourceFormat}, bytes=${failure.safeByteSize}, '
      'outputExists=${failure.outputExists}, '
      'errorType=${failure.cause.runtimeType}',
    );
    debugPrintStack(stackTrace: failure.stackTrace);
  }

  static String _safeSourceFormat(XFile file) {
    final mime = file.mimeType?.toLowerCase();
    if (mime != null && mime.startsWith('image/')) {
      return mime.substring('image/'.length).replaceAll('x-', '');
    }
    final extension = _extensionFromName(file.name);
    return extension.isEmpty ? 'unknown' : extension;
  }

  static String _safeSourceExtension(XFile file, Uint8List bytes) {
    final detectedExtension = switch (_detectImageFormat(bytes)) {
      'jpeg' => 'jpg',
      'png' => 'png',
      'webp' => 'webp',
      'heic' => 'heic',
      'gif' => 'gif',
      'avif' => 'avif',
      'bmp' => 'bmp',
      _ => null,
    };
    if (detectedExtension != null) return detectedExtension;

    final mimeSubtype = file.mimeType
        ?.toLowerCase()
        .replaceFirst('image/x-', '')
        .replaceFirst('image/', '');
    if (mimeSubtype == 'jpeg') return 'jpg';
    const supportedExtensions = <String>{
      'jpg',
      'png',
      'webp',
      'heic',
      'heif',
      'gif',
      'avif',
      'bmp',
    };
    if (mimeSubtype != null && supportedExtensions.contains(mimeSubtype)) {
      return mimeSubtype;
    }
    final extension = _extensionFromName(file.name);
    if (extension == 'jpeg') return 'jpg';
    return supportedExtensions.contains(extension) ? extension : 'img';
  }

  static String _extensionFromName(String name) {
    final separator = name.lastIndexOf('.');
    if (separator < 0 || separator == name.length - 1) return '';
    return name.substring(separator + 1).toLowerCase();
  }

  static ImageCropRatio _cropRatio(SocialPostAspectRatio ratio) =>
      switch (ratio) {
        SocialPostAspectRatio.square => ImageCropRatio.square,
        SocialPostAspectRatio.portrait => ImageCropRatio.portraitFourByFive,
        SocialPostAspectRatio.landscape => ImageCropRatio.square,
      };

  Future<CroppedPostMedia?> _legacyCropResult(
    XFile source,
    ImageCropRatio ratio,
  ) async {
    final cropped = await _cropImageOverride!(source, ratio);
    return cropped == null
        ? null
        : CroppedPostMedia(croppedFile: cropped, selectedAspectRatio: ratio);
  }

  static SocialPostAspectRatio _socialAspectRatio(ImageCropRatio ratio) =>
      switch (ratio) {
        ImageCropRatio.square => SocialPostAspectRatio.square,
        ImageCropRatio.portraitFourByFive => SocialPostAspectRatio.portrait,
      };
}

class _PreparedOutcome {
  const _PreparedOutcome({
    required this.media,
    required this.optimized,
    required this.selectedAspectRatio,
  });
  final SocialPostPreparedMedia media;
  final bool optimized;
  final SocialPostAspectRatio selectedAspectRatio;
}

class _PreparedBytes {
  const _PreparedBytes(this.bytes, {required this.optimized});
  final Uint8List bytes;
  final bool optimized;
}

String _detectImageFormat(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
    return 'webp';
  }
  if (bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(4, 8)) == 'ftyp') {
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    if (brand.startsWith('hei') || brand == 'mif1' || brand == 'msf1') {
      return 'heic';
    }
    if (brand == 'avif' || brand == 'avis') return 'avif';
  }
  if (bytes.length >= 6) {
    final signature = String.fromCharCodes(bytes.sublist(0, 6));
    if (signature == 'GIF87a' || signature == 'GIF89a') return 'gif';
  }
  if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4d) {
    return 'bmp';
  }
  return 'unknown';
}

bool _isReadableImage(Uint8List bytes) => img.decodeImage(bytes) != null;

bool _isReadableJpeg(Uint8List bytes) =>
    _detectImageFormat(bytes) == 'jpeg' && img.decodeImage(bytes) != null;

Uint8List? _optimizeSocialPostImage(Uint8List bytes) {
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
    final resized = longest > maxDimension
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height ? maxDimension : null,
            height: oriented.height > oriented.width ? maxDimension : null,
          )
        : oriented;
    final candidate = img.Image(
      width: resized.width,
      height: resized.height,
      numChannels: 3,
    );
    img.fill(candidate, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(candidate, resized);
    final encoded = Uint8List.fromList(
      img.encodeJpg(candidate, quality: quality),
    );
    if (encoded.length <= socialPostMaxUploadBytes) return encoded;
    oriented = resized;
  }
  return null;
}
