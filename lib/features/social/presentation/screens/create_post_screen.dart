import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/image_crop_service.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/services/post_publish_coordinator.dart';
import '../../data/social_post_repository.dart';
import '../../domain/models/social_post_model.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const int _maxPostImages = 5;
  static const int _maxHashtags = 5;
  static const List<SocialPostAspectRatio> _supportedAspectRatios =
      <SocialPostAspectRatio>[
        SocialPostAspectRatio.square,
        SocialPostAspectRatio.portrait,
      ];

  final SocialPostRepository _repository = SocialPostRepository();
  final ImagePicker _imagePicker = ImagePicker();
  final ImageCropService _imageCropService = ImageCropService();
  final PostPublishCoordinator _publishCoordinator =
      PostPublishCoordinator.instance;
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _hashtagController = TextEditingController();

  final List<XFile> _selectedImages = <XFile>[];
  final List<String> _hashtags = <String>[];
  SocialPostAspectRatio _aspectRatio = SocialPostAspectRatio.square;
  bool _isPublishing = false;
  int _previewIndex = 0;

  @override
  void initState() {
    super.initState();
    _restoreRecoverableDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(
        context,
      )) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    _hashtagController.dispose();
    super.dispose();
  }

  void _restoreRecoverableDraft() {
    final draft = _publishCoordinator.takeRecoverableDraft();
    if (draft == null) return;

    _captionController.text = draft.caption;
    _selectedImages
      ..clear()
      ..addAll(draft.toImages());
    _hashtags
      ..clear()
      ..addAll(draft.hashtags);
    _aspectRatio = draft.aspectRatio;
  }

  Future<void> _pickImages() async {
    final picked = await _imagePicker.pickMultiImage(imageQuality: 100);
    if (!mounted) return;
    if (picked.isEmpty) return;

    final remainingSlots = _maxPostImages - _selectedImages.length;
    if (remainingSlots <= 0) {
      AppFeedback.show(
        context,
        message: 'You can add up to $_maxPostImages images per post.',
        tone: AppFeedbackTone.warning,
      );
      return;
    }

    if (picked.length > remainingSlots) {
      AppFeedback.show(
        context,
        message:
            'Only the first $remainingSlots images can be added right now.',
        tone: AppFeedbackTone.info,
      );
    }

    final croppedImages = <XFile>[];
    var cancelledCount = 0;
    var failedCropCount = 0;
    for (final file in picked.take(remainingSlots)) {
      final croppedImage = await _imageCropService.cropImage(
        source: file,
        context: ImageCropContext.post,
        ratio: _cropRatioForPost(_aspectRatio),
      );
      if (!mounted) return;
      if (croppedImage == null) {
        if (_imageCropService.hadLastError) {
          failedCropCount += 1;
        } else {
          cancelledCount += 1;
        }
        continue;
      }
      croppedImages.add(XFile(croppedImage.path));
    }

    if (!mounted) return;
    if (cancelledCount > 0) {
      AppFeedback.show(
        context,
        message: croppedImages.isEmpty
            ? 'Image cropping was cancelled.'
            : '$cancelledCount image ${cancelledCount == 1 ? 'was' : 'were'} skipped because cropping was cancelled.',
        tone: AppFeedbackTone.info,
      );
    }
    if (failedCropCount > 0) {
      AppFeedback.show(
        context,
        message: failedCropCount == 1
            ? 'Image crop failed. Please try again.'
            : '$failedCropCount images failed to crop. Please try again.',
        tone: AppFeedbackTone.error,
      );
    }
    if (croppedImages.isEmpty) return;

    setState(() {
      _selectedImages.addAll(croppedImages);
      _previewIndex = 0;
    });
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      if (_previewIndex >= _selectedImages.length) {
        _previewIndex = _selectedImages.isEmpty
            ? 0
            : _selectedImages.length - 1;
      }
    });
  }

  void _addHashtag() {
    if (_hashtags.length >= _maxHashtags) {
      AppFeedback.show(
        context,
        message: 'You can add up to $_maxHashtags hashtags.',
        tone: AppFeedbackTone.warning,
      );
      return;
    }

    final normalized = _repository.normalizeHashtag(_hashtagController.text);
    if (normalized.isEmpty) {
      AppFeedback.show(
        context,
        message: 'Use hashtags without spaces.',
        tone: AppFeedbackTone.warning,
      );
      return;
    }
    if (_hashtags.contains(normalized)) {
      _hashtagController.clear();
      return;
    }

    setState(() {
      _hashtags.add(normalized);
      _hashtagController.clear();
    });
  }

  Future<void> _publish() async {
    if (_selectedImages.isEmpty || _isPublishing) return;

    final started = _publishCoordinator.startPublish(
      images: List<XFile>.from(_selectedImages),
      aspectRatio: _aspectRatio,
      caption: _captionController.text,
      hashtags: _hashtags,
    );
    if (!started) {
      return;
    }

    setState(() => _isPublishing = true);
    if (!mounted) return;
    Navigator.pop(context);
  }

  void _selectAspectRatio(SocialPostAspectRatio ratio) {
    if (ratio == _aspectRatio) return;
    if (_selectedImages.isNotEmpty) {
      AppFeedback.show(
        context,
        message:
            'Remove selected images before switching between Square 1:1 and Portrait 4:5.',
        tone: AppFeedbackTone.info,
      );
      return;
    }

    setState(() => _aspectRatio = ratio);
  }

  double get _previewAspectRatio {
    switch (_aspectRatio) {
      case SocialPostAspectRatio.square:
        return 1;
      case SocialPostAspectRatio.portrait:
        return 4 / 5;
      case SocialPostAspectRatio.landscape:
        return 1.91;
    }
  }

  ImageCropRatio _cropRatioForPost(SocialPostAspectRatio ratio) {
    return switch (ratio) {
      SocialPostAspectRatio.square => ImageCropRatio.square,
      SocialPostAspectRatio.portrait => ImageCropRatio.portraitFourByFive,
      SocialPostAspectRatio.landscape => ImageCropRatio.square,
    };
  }

  @override
  Widget build(BuildContext context) {
    final canPublish = _selectedImages.isNotEmpty && !_isPublishing;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F1),
      extendBody: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: _CreatePostHeader(
                isPublishing: _isPublishing,
                canPublish: canPublish,
                onBack: () => Navigator.pop(context),
                onPublish: canPublish ? _publish : null,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 132),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionLabel(
                      label: 'ASPECT RATIO',
                      helper: 'Choose once before selecting images.',
                    ),
                    const SizedBox(height: 10),
                    _AspectRatioSelector(
                      ratios: _supportedAspectRatios,
                      selectedRatio: _aspectRatio,
                      onSelected: _selectAspectRatio,
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(
                      label:
                          'PHOTOS · ${_selectedImages.length}/$_maxPostImages',
                    ),
                    const SizedBox(height: 10),
                    _ImagePreview(
                      images: _selectedImages,
                      maxImages: _maxPostImages,
                      aspectRatio: _previewAspectRatio,
                      previewIndex: _previewIndex,
                      onPageChanged: (value) =>
                          setState(() => _previewIndex = value),
                      onRemove: _removeImage,
                      onSelectImages: _selectedImages.length >= _maxPostImages
                          ? null
                          : _pickImages,
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(label: 'CAPTION'),
                    const SizedBox(height: 10),
                    _CaptionInputCard(controller: _captionController),
                    const SizedBox(height: 24),
                    _SectionLabel(
                      label: 'HASHTAGS',
                      helper:
                          'Add up to $_maxHashtags hashtags to help others find your post.',
                    ),
                    const SizedBox(height: 10),
                    _HashtagInputRow(
                      controller: _hashtagController,
                      onAdd: _addHashtag,
                    ),
                    if (_hashtags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _HashtagChips(
                        hashtags: _hashtags,
                        onRemoved: (tag) =>
                            setState(() => _hashtags.remove(tag)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SocialBottomNav(activeTab: null),
    );
  }
}

class _CreatePostHeader extends StatelessWidget {
  final bool isPublishing;
  final bool canPublish;
  final VoidCallback onBack;
  final VoidCallback? onPublish;

  const _CreatePostHeader({
    required this.isPublishing,
    required this.canPublish,
    required this.onBack,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          child: Material(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(16),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'Create Post',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
        ),
        const SizedBox(width: 14),
        _PublishPill(
          isPublishing: isPublishing,
          enabled: canPublish,
          onPressed: onPublish,
        ),
      ],
    );
  }
}

class _PublishPill extends StatelessWidget {
  final bool isPublishing;
  final bool enabled;
  final VoidCallback? onPressed;

  const _PublishPill({
    required this.isPublishing,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = enabled
        ? AppColors.primary
        : AppColors.primary.withValues(alpha: 0.28);
    final foregroundColor = enabled
        ? AppColors.primary
        : AppColors.primary.withValues(alpha: 0.48);

    return Semantics(
      button: true,
      enabled: enabled,
      label: isPublishing ? 'Publishing post' : 'Publish post',
      child: Material(
        color: enabled
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 88),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: borderColor, width: 1.2),
            ),
            child: Center(
              child: isPublishing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: foregroundColor,
                      ),
                    )
                  : Text(
                      'Share',
                      style: TextStyle(
                        color: foregroundColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final String? helper;

  const _SectionLabel({required this.label, this.helper});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textGrey.withValues(alpha: 0.88),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 6),
          Text(
            helper!,
            style: TextStyle(
              color: AppColors.textGrey.withValues(alpha: 0.82),
              height: 1.38,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class _AspectRatioSelector extends StatelessWidget {
  final List<SocialPostAspectRatio> ratios;
  final SocialPostAspectRatio selectedRatio;
  final ValueChanged<SocialPostAspectRatio> onSelected;

  const _AspectRatioSelector({
    required this.ratios,
    required this.selectedRatio,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: ratios
            .map((ratio) {
              final selected = ratio == selectedRatio;
              return Expanded(
                child: Material(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                  child: InkWell(
                    onTap: () => onSelected(ratio),
                    borderRadius: BorderRadius.circular(17),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      constraints: const BoxConstraints(minHeight: 46),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.transparent,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        _ratioLabel(ratio),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? AppColors.primary
                              : AppColors.textDark,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _CaptionInputCard extends StatelessWidget {
  final TextEditingController controller;

  const _CaptionInputCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: controller,
            maxLines: 6,
            minLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: _softInputDecoration(
              hintText: 'Write a caption for your pet moment...',
              borderRadius: 22,
              fillColor: Colors.transparent,
              borderColor: Colors.transparent,
              contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              return Text(
                '${value.text.characters.length}',
                style: TextStyle(
                  color: AppColors.textGrey.withValues(alpha: 0.76),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HashtagInputRow extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onAdd;

  const _HashtagInputRow({required this.controller, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onAdd(),
            decoration: _softInputDecoration(
              hintText: 'Add a hashtag like puppyplaydate',
            ),
          ),
        ),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: 'Add hashtag',
          child: Material(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(17),
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(17),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52, minWidth: 72),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.68),
                  ),
                ),
                child: const Text(
                  'Add',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HashtagChips extends StatelessWidget {
  final List<String> hashtags;
  final ValueChanged<String> onRemoved;

  const _HashtagChips({required this.hashtags, required this.onRemoved});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: hashtags
          .map((tag) {
            return Chip(
              label: Text(
                '#$tag',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              onDeleted: () => onRemoved(tag),
              deleteIconColor: AppColors.primary,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              side: BorderSide(
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class _SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _SoftCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

InputDecoration _softInputDecoration({
  required String hintText,
  double borderRadius = 22,
  Color? fillColor,
  Color? borderColor,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 16,
  ),
}) {
  final effectiveFill = fillColor ?? Colors.white.withValues(alpha: 0.86);
  final effectiveBorder =
      borderColor ?? AppColors.primary.withValues(alpha: 0.08);

  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(
      color: AppColors.textGrey.withValues(alpha: 0.78),
      fontWeight: FontWeight.w500,
    ),
    filled: true,
    fillColor: effectiveFill,
    contentPadding: contentPadding,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(color: effectiveBorder),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(color: effectiveBorder),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
    ),
  );
}

class _ImagePreview extends StatelessWidget {
  final List<XFile> images;
  final int maxImages;
  final double aspectRatio;
  final int previewIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRemove;
  final VoidCallback? onSelectImages;

  const _ImagePreview({
    required this.images,
    required this.maxImages,
    required this.aspectRatio,
    required this.previewIndex,
    required this.onPageChanged,
    required this.onRemove,
    this.onSelectImages,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return _AddPhotoTile(
        onTap: onSelectImages,
        title: 'Add',
        subtitle: 'Select up to $maxImages photos',
      );
    }

    return _SoftCard(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: Stack(
                children: [
                  PageView.builder(
                    itemCount: images.length,
                    onPageChanged: onPageChanged,
                    itemBuilder: (context, index) {
                      return Container(
                        color: const Color(0xFFFFEFE5),
                        child: Image.file(
                          File(images[index].path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFFFFF2EA),
                            child: const Center(
                              child: Icon(
                                Icons.image_outlined,
                                color: AppColors.textGrey,
                                size: 42,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        onTap: () => onRemove(previewIndex),
                        borderRadius: BorderRadius.circular(16),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length + (images.length < maxImages ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index >= images.length) {
                  return SizedBox(
                    width: 76,
                    child: _AddPhotoTile(
                      onTap: onSelectImages,
                      compact: true,
                      title: 'Add',
                    ),
                  );
                }

                final active = previewIndex == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: active
                          ? AppColors.primary
                          : Colors.white.withValues(alpha: 0.8),
                      width: active ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(images[index].path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: Color(0xFFFFF2EA),
                        child: Icon(
                          Icons.image_outlined,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  final VoidCallback? onTap;
  final bool compact;
  final String title;
  final String? subtitle;

  const _AddPhotoTile({
    required this.onTap,
    required this.title,
    this.compact = false,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(compact ? 18 : 28);

    return Semantics(
      button: true,
      enabled: onTap != null,
      label: 'Add photo',
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: AppColors.primary.withValues(alpha: 0.72),
              radius: compact ? 18 : 28,
            ),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 8 : 24,
                vertical: compact ? 8 : 34,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.045),
                borderRadius: radius,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    color: AppColors.primary,
                    size: compact ? 24 : 44,
                  ),
                  SizedBox(height: compact ? 4 : 10),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: compact ? 12 : 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      subtitle!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textGrey.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    const dashWidth = 9.0;
    const dashGap = 6.0;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashWidth + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

String _ratioLabel(SocialPostAspectRatio ratio) {
  return switch (ratio) {
    SocialPostAspectRatio.square => 'Square 1:1',
    SocialPostAspectRatio.portrait => 'Portrait 4:5',
    SocialPostAspectRatio.landscape => 'Landscape',
  };
}
