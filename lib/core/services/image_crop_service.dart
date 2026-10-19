import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';

enum ImageCropContext { post, profile, service, chat }

enum ImageCropRatio { square, portraitFourByFive }

@immutable
class CroppedPostMedia {
  const CroppedPostMedia({
    required this.croppedFile,
    required this.selectedAspectRatio,
  });

  final File croppedFile;
  final ImageCropRatio selectedAspectRatio;
}

class _PostCropAspectRatioPreset implements CropAspectRatioPresetData {
  const _PostCropAspectRatioPreset(this.name, this.ratioX, this.ratioY);

  @override
  final String name;
  final int ratioX;
  final int ratioY;

  @override
  (int ratioX, int ratioY) get data => (ratioX, ratioY);
}

const _squarePostCropPreset = _PostCropAspectRatioPreset('Square 1:1', 1, 1);
const _portraitPostCropPreset = _PostCropAspectRatioPreset(
  'Portrait 4:5',
  4,
  5,
);

@visibleForTesting
const List<CropAspectRatioPresetData> socialPostCropAspectRatioPresets =
    <CropAspectRatioPresetData>[_squarePostCropPreset, _portraitPostCropPreset];
const List<CropAspectRatioPresetData> _iosPostCropAspectRatioPresets =
    <CropAspectRatioPresetData>[
      CropAspectRatioPreset.square,
      _portraitPostCropPreset,
    ];

@visibleForTesting
ImageCompressFormat socialPostCropCompressFormatForSource(XFile source) {
  final normalizedPath = source.path.toLowerCase();
  final normalizedMime = source.mimeType?.toLowerCase();
  return const <String>{
            'image/png',
            'image/webp',
            'image/gif',
            'image/avif',
            'image/bmp',
            'image/x-bmp',
          }.contains(normalizedMime) ||
          normalizedPath.endsWith('.png') ||
          normalizedPath.endsWith('.webp') ||
          normalizedPath.endsWith('.gif') ||
          normalizedPath.endsWith('.avif') ||
          normalizedPath.endsWith('.bmp')
      ? ImageCompressFormat.png
      : ImageCompressFormat.jpg;
}

@visibleForTesting
AndroidUiSettings socialPostAndroidCropSettings({
  required ImageCropRatio ratio,
  required bool allowRatioSelection,
  String toolbarTitle = 'Crop image',
}) => AndroidUiSettings(
  toolbarTitle: toolbarTitle,
  toolbarColor: const Color(0xCCFCF8F5),
  toolbarWidgetColor: AppColors.textDark,
  // ignore: deprecated_member_use
  statusBarColor: const Color(0xCCFCF8F5),
  statusBarLight: true,
  navBarLight: true,
  activeControlsWidgetColor: AppColors.primary,
  cropFrameColor: AppColors.primary,
  cropGridColor: AppColors.primary.withValues(alpha: 0.4),
  dimmedLayerColor: Colors.black.withValues(alpha: 0.55),
  backgroundColor: Colors.black,
  // Keep uCrop's frame constrained; visible preset controls can still switch
  // it between the two supported ratios.
  lockAspectRatio: true,
  hideBottomControls: !allowRatioSelection,
  aspectRatioPresets: socialPostCropAspectRatioPresets,
  initAspectRatio: ratio == ImageCropRatio.square
      ? _squarePostCropPreset
      : _portraitPostCropPreset,
);

class ImageCropService {
  ImageCropService({ImageCropper? cropper})
    : _cropper = cropper ?? ImageCropper();

  final ImageCropper _cropper;
  static const MethodChannel _postCropResultChannel = MethodChannel(
    'com.pettexo.app/post_crop_result',
  );
  bool _hadLastError = false;
  Object? _lastError;
  StackTrace? _lastStackTrace;

  bool get hadLastError => _hadLastError;
  Object? get lastError => _lastError;
  StackTrace? get lastStackTrace => _lastStackTrace;

  Future<CroppedPostMedia?> cropPostImage({
    required XFile source,
    required ImageCropRatio initialRatio,
    required bool allowRatioSelection,
  }) async {
    _hadLastError = false;
    _lastError = null;
    _lastStackTrace = null;

    try {
      if (Platform.isAndroid) {
        try {
          await _postCropResultChannel.invokeMethod<void>('beginPostCrop');
        } on MissingPluginException {
          // A dimension-based fallback is used below on unsupported embedders.
        }
      }

      final cropped = await _cropper.cropImage(
        sourcePath: source.path,
        // Android uses initAspectRatio below. Supplying this argument would
        // force-lock the iOS cropper and hide its ratio picker.
        aspectRatio: allowRatioSelection ? null : initialRatio.aspectRatio,
        compressFormat: socialPostCropCompressFormatForSource(source),
        compressQuality: 100,
        uiSettings: [
          _androidSettings(
            ImageCropContext.post,
            ratio: initialRatio,
            allowRatioSelection: allowRatioSelection,
          ),
          _iosSettings(
            ImageCropContext.post,
            allowRatioSelection: allowRatioSelection,
          ),
        ],
      );
      if (cropped == null) return null;

      final file = File(cropped.path);
      final selectedRatio = allowRatioSelection
          ? await _selectedPostRatio(file, fallback: initialRatio)
          : initialRatio;
      return CroppedPostMedia(
        croppedFile: file,
        selectedAspectRatio: selectedRatio,
      );
    } on PlatformException catch (error, stackTrace) {
      _recordCropFailure(error, stackTrace);
      return null;
    } catch (error, stackTrace) {
      _recordCropFailure(error, stackTrace);
      return null;
    }
  }

  Future<File?> cropImage({
    required XFile source,
    required ImageCropContext context,
    required ImageCropRatio ratio,
  }) async {
    _hadLastError = false;
    _lastError = null;
    _lastStackTrace = null;

    try {
      final cropFormat = context == ImageCropContext.post
          ? socialPostCropCompressFormatForSource(source)
          : ImageCompressFormat.jpg;
      final cropped = await _cropper.cropImage(
        sourcePath: source.path,
        aspectRatio: ratio.aspectRatio,
        compressFormat: cropFormat,
        compressQuality: 100,
        uiSettings: [
          _androidSettings(context, ratio: ratio),
          _iosSettings(context),
        ],
      );

      if (cropped == null) return null;
      return File(cropped.path);
    } on PlatformException catch (error, stackTrace) {
      _hadLastError = true;
      _lastError = error;
      _lastStackTrace = stackTrace;
      if (kDebugMode) {
        debugPrint(
          'ImageCropService crop failed: stage=native-cropper, '
          'errorType=${error.runtimeType}, code=${error.code}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      return null;
    } catch (error, stackTrace) {
      _hadLastError = true;
      _lastError = error;
      _lastStackTrace = stackTrace;
      if (kDebugMode) {
        debugPrint(
          'ImageCropService crop failed: stage=native-cropper, '
          'errorType=${error.runtimeType}',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
      return null;
    }
  }

  Future<File?> cropChatImage({required XFile source}) async {
    _hadLastError = false;
    try {
      final cropped = await _cropper.cropImage(
        sourcePath: source.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 100,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: _toolbarTitle(ImageCropContext.chat),
            toolbarColor: const Color(0xCCFCF8F5),
            toolbarWidgetColor: AppColors.textDark,
            // ignore: deprecated_member_use
            statusBarColor: const Color(0xCCFCF8F5),
            statusBarLight: true,
            navBarLight: true,
            activeControlsWidgetColor: AppColors.primary,
            cropFrameColor: AppColors.primary,
            cropGridColor: AppColors.primary.withValues(alpha: 0.4),
            dimmedLayerColor: Colors.black.withValues(alpha: 0.55),
            backgroundColor: Colors.black,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: _toolbarTitle(ImageCropContext.chat),
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
            embedInNavigationController: true,
            hidesNavigationBar: false,
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: false,
            aspectRatioPickerButtonHidden: false,
          ),
        ],
      );
      return cropped == null ? null : File(cropped.path);
    } on PlatformException catch (error, stackTrace) {
      _hadLastError = true;
      debugPrint('ImageCropService chat crop failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    } catch (error, stackTrace) {
      _hadLastError = true;
      debugPrint('ImageCropService chat crop failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  String _toolbarTitle(ImageCropContext context) {
    return switch (context) {
      ImageCropContext.post => 'Crop image',
      ImageCropContext.profile => 'Crop profile photo',
      ImageCropContext.service => 'Crop service photo',
      ImageCropContext.chat => 'Crop photo',
    };
  }

  AndroidUiSettings _androidSettings(
    ImageCropContext context, {
    required ImageCropRatio ratio,
    bool allowRatioSelection = false,
  }) => socialPostAndroidCropSettings(
    toolbarTitle: _toolbarTitle(context),
    ratio: ratio,
    allowRatioSelection: allowRatioSelection,
  );

  IOSUiSettings _iosSettings(
    ImageCropContext context, {
    bool allowRatioSelection = false,
  }) => IOSUiSettings(
    title: _toolbarTitle(context),
    doneButtonTitle: 'Done',
    cancelButtonTitle: 'Cancel',
    embedInNavigationController: true,
    hidesNavigationBar: false,
    aspectRatioLockEnabled: !allowRatioSelection,
    resetAspectRatioEnabled: allowRatioSelection,
    rotateButtonsHidden: false,
    rotateClockwiseButtonHidden: false,
    aspectRatioPickerButtonHidden: !allowRatioSelection,
    aspectRatioPresets: _iosPostCropAspectRatioPresets,
    rectX: 0,
    rectY: 0,
    rectWidth: 1,
    rectHeight: 1,
  );

  Future<ImageCropRatio> _selectedPostRatio(
    File croppedFile, {
    required ImageCropRatio fallback,
  }) async {
    if (Platform.isAndroid) {
      try {
        final nativeRatio = await _postCropResultChannel.invokeMethod<double>(
          'takePostCropAspectRatio',
        );
        if (nativeRatio != null) return _closestPostRatio(nativeRatio);
      } on MissingPluginException {
        // Continue to the cross-platform output-dimension fallback.
      } on PlatformException {
        // Continue to the cross-platform output-dimension fallback.
      }
    }

    try {
      final decoded = img.decodeImage(await croppedFile.readAsBytes());
      if (decoded != null && decoded.height > 0) {
        return _closestPostRatio(decoded.width / decoded.height);
      }
    } catch (_) {
      // The crop itself succeeded; retain its requested initial ratio.
    }
    return fallback;
  }

  ImageCropRatio _closestPostRatio(double ratio) {
    return (ratio - 1).abs() <= (ratio - (4 / 5)).abs()
        ? ImageCropRatio.square
        : ImageCropRatio.portraitFourByFive;
  }

  void _recordCropFailure(Object error, StackTrace stackTrace) {
    _hadLastError = true;
    _lastError = error;
    _lastStackTrace = stackTrace;
    if (kDebugMode) {
      final code = error is PlatformException ? ', code=${error.code}' : '';
      debugPrint(
        'ImageCropService crop failed: stage=native-cropper, '
        'errorType=${error.runtimeType}$code',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}

extension on ImageCropRatio {
  CropAspectRatio get aspectRatio {
    return switch (this) {
      ImageCropRatio.square => const CropAspectRatio(ratioX: 1, ratioY: 1),
      ImageCropRatio.portraitFourByFive => const CropAspectRatio(
        ratioX: 4,
        ratioY: 5,
      ),
    };
  }
}
