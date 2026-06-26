import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../data/social_post_repository.dart';
import '../../domain/models/social_post_model.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final SocialPostRepository _repository = SocialPostRepository();
  final ImagePicker _imagePicker = ImagePicker();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
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

  Future<void> _pickImages() async {
    final picked = await _imagePicker.pickMultiImage(imageQuality: 100);
    if (!mounted) return;
    if (picked.isEmpty) return;

    final nextImages = <XFile>[..._selectedImages, ...picked];
    if (nextImages.length > 5) {
      AppFeedback.show(
        context,
        message: 'You can add up to 5 images per post.',
        tone: AppFeedbackTone.warning,
      );
    }

    setState(() {
      _selectedImages
        ..clear()
        ..addAll(nextImages.take(5));
      _previewIndex = 0;
    });
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      if (_previewIndex >= _selectedImages.length) {
        _previewIndex = _selectedImages.isEmpty ? 0 : _selectedImages.length - 1;
      }
    });
  }

  void _addHashtag() {
    if (_hashtags.length >= 5) {
      AppFeedback.show(
        context,
        message: 'You can add up to 5 hashtags.',
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

    setState(() => _isPublishing = true);
    try {
      final post = await _repository.createPost(
        images: _selectedImages,
        aspectRatio: _aspectRatio,
        caption: _captionController.text,
        hashtags: _hashtags,
      );
      if (!mounted) return;
      Navigator.pop(context, post);
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 132),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(onClose: () => Navigator.pop(context)),
              const SizedBox(height: 18),
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Images',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _ImagePreview(
                      images: _selectedImages,
                      aspectRatio: _previewAspectRatio,
                      previewIndex: _previewIndex,
                      onPageChanged: (value) => setState(() => _previewIndex = value),
                      onRemove: _removeImage,
                      onSelectImages: _selectedImages.length >= 5
                          ? null
                          : _pickImages,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Aspect ratio',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: SocialPostAspectRatio.values.map((ratio) {
                        final selected = ratio == _aspectRatio;
                        return InkWell(
                          onTap: () => setState(() => _aspectRatio = ratio),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: selected ? AppColors.brandGradient : null,
                              color: selected ? null : const Color(0xFFFFF4E8),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              ratio.label,
                              style: TextStyle(
                                color: selected ? Colors.white : AppColors.textDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }).toList(growable: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Caption',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _captionController,
                      maxLines: 4,
                      minLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _inputDecoration(
                        hintText: 'Write a caption for your pet moment...',
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Hashtags',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _hashtagController,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addHashtag(),
                            decoration: _inputDecoration(
                              hintText: 'Add a hashtag like puppyplaydate',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SecondaryButton(
                          label: 'Add',
                          expand: false,
                          size: AppButtonSize.compact,
                          onPressed: _addHashtag,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _hashtags.map((tag) {
                        return Chip(
                          label: Text(
                            '#$tag',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onDeleted: () => setState(() => _hashtags.remove(tag)),
                          deleteIconColor: AppColors.primary,
                          backgroundColor: const Color(0xFFFFF4EC),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                            side: BorderSide.none,
                          ),
                        );
                      }).toList(growable: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GradientButton(
                label: _isPublishing ? 'Publishing...' : 'Publish Post',
                onPressed: _selectedImages.isEmpty || _isPublishing ? null : _publish,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const SocialBottomNav(activeTab: null),
    );
  }

  InputDecoration _inputDecoration({required String hintText}) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: const Color(0xFFFFFBF8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.08),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.08),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(20),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onClose;

  const _Header({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Post',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Share image-only moments from around Pettxo.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;

  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 26,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ImagePreview extends StatelessWidget {
  final List<XFile> images;
  final double aspectRatio;
  final int previewIndex;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRemove;
  final VoidCallback? onSelectImages;

  const _ImagePreview({
    required this.images,
    required this.aspectRatio,
    required this.previewIndex,
    required this.onPageChanged,
    required this.onRemove,
    this.onSelectImages,
  });

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelectImages,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF8),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppColors.textGrey.withValues(alpha: 0.2),
              ),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 48,
                  color: AppColors.textGrey,
                ),
                SizedBox(height: 12),
                Text(
                  'Select up to 5 images to start your post.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Images will be resized and compressed before upload.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textGrey,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
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
                      color: const Color(0xFFFCF8F5),
                      child: Image.file(
                        File(images[index].path),
                        fit: BoxFit.contain,
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
                  child: CircleAvatar(
                    backgroundColor: Colors.black.withValues(alpha: 0.45),
                    child: IconButton(
                      onPressed: () => onRemove(previewIndex),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(images.length, (index) {
            final active = previewIndex == index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }
}
