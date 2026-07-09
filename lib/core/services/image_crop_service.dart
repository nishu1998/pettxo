import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';

enum ImageCropContext { post, profile, service }

enum ImageCropRatio { square, portraitFourByFive }

class ImageCropService {
  ImageCropService({ImageCropper? cropper})
    : _cropper = cropper ?? ImageCropper();

  final ImageCropper _cropper;
  bool _hadLastError = false;

  bool get hadLastError => _hadLastError;

  Future<File?> cropImage({
    required XFile source,
    required ImageCropContext context,
    required ImageCropRatio ratio,
  }) async {
    _hadLastError = false;

    try {
      final cropped = await _cropper.cropImage(
        sourcePath: source.path,
        aspectRatio: ratio.aspectRatio,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 100,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: _toolbarTitle(context),
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
            lockAspectRatio: true,
            hideBottomControls: true,
          ),
          IOSUiSettings(
            title: _toolbarTitle(context),
            doneButtonTitle: 'Done',
            cancelButtonTitle: 'Cancel',
            embedInNavigationController: true,
            hidesNavigationBar: false,
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: false,
            aspectRatioPickerButtonHidden: true,
            rectX: 0,
            rectY: 0,
            rectWidth: 1,
            rectHeight: 1,
          ),
        ],
      );

      if (cropped == null) return null;
      return File(cropped.path);
    } on PlatformException catch (error, stackTrace) {
      _hadLastError = true;
      debugPrint('ImageCropService crop failed with platform error: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    } catch (error, stackTrace) {
      _hadLastError = true;
      debugPrint('ImageCropService crop failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  String _toolbarTitle(ImageCropContext context) {
    return switch (context) {
      ImageCropContext.post => 'Crop image',
      ImageCropContext.profile => 'Crop profile photo',
      ImageCropContext.service => 'Crop service photo',
    };
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
