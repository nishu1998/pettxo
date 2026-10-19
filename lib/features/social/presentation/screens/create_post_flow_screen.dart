import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/pettxo_loading_animation.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../application/social_post_media_preparation_service.dart';
import '../../data/services/post_publish_coordinator.dart';
import '../../domain/models/social_post_model.dart';
import 'create_post_screen.dart';

class CreatePostFlowLauncher {
  CreatePostFlowLauncher._();

  static bool _isOpening = false;

  static Future<void> open(
    BuildContext context, {
    bool checkRestrictions = true,
  }) async {
    if (_isOpening) return;
    if (checkRestrictions &&
        !UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }
    _isOpening = true;
    try {
      await Navigator.of(context).pushNamed('/create');
    } finally {
      _isOpening = false;
    }
  }

  @visibleForTesting
  static void resetForTesting() => _isOpening = false;
}

class CreatePostFlowScreen extends StatefulWidget {
  const CreatePostFlowScreen({
    super.key,
    this.preparationService,
    this.checkRestrictions = true,
    this.composerBuilder,
    this.hasRecoverableDraft,
    this.aspectRatioChooser,
  });

  final SocialPostMediaPreparationService? preparationService;
  final bool checkRestrictions;
  final Widget Function(List<XFile> images)? composerBuilder;
  final bool Function()? hasRecoverableDraft;
  final Future<SocialPostAspectRatio?> Function(BuildContext context)?
  aspectRatioChooser;

  @override
  State<CreatePostFlowScreen> createState() => _CreatePostFlowScreenState();
}

class _CreatePostFlowScreenState extends State<CreatePostFlowScreen> {
  late final SocialPostMediaPreparationService _preparationService;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _preparationService =
        widget.preparationService ?? SocialPostMediaPreparationService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started || !mounted) return;
    _started = true;
    if (widget.checkRestrictions &&
        !UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      Navigator.of(context).pop();
      return;
    }
    final recoverableDraftExists =
        widget.hasRecoverableDraft?.call() ??
        PostPublishCoordinator.instance.peekRecoverableDraft() != null;
    if (recoverableDraftExists) {
      unawaited(
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const CreatePostScreen(),
            settings: const RouteSettings(name: '/create/composer'),
          ),
        ),
      );
      return;
    }

    final picked = await _preparationService.pickGalleryImages();
    if (!mounted) return;
    if (picked.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final aspectRatio =
        await (widget.aspectRatioChooser?.call(context) ??
            _chooseInitialAspectRatio(context));
    if (!mounted) return;
    if (aspectRatio == null) {
      Navigator.of(context).pop();
      return;
    }
    final result = await _preparationService.preparePickedImages(
      picked: picked,
      maxImages: 5,
      aspectRatio: aspectRatio,
    );
    if (!mounted) {
      await SocialPostMediaPreparationService.deletePreparedImages(
        result.images,
      );
      return;
    }
    _showPreparationFeedback(context, result);
    if (result.images.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    unawaited(
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              widget.composerBuilder?.call(result.images) ??
              CreatePostScreen(
                initialImages: result.images,
                initialAspectRatio: aspectRatio,
              ),
          settings: const RouteSettings(name: '/create/composer'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFFFF8F1),
      body: Center(
        child: PettxoLoader.fullScreen(
          semanticLabel: 'Preparing selected photos',
          message: 'Preparing your photos…',
        ),
      ),
    );
  }
}

Future<SocialPostAspectRatio?> _chooseInitialAspectRatio(BuildContext context) {
  return showModalBottomSheet<SocialPostAspectRatio>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Choose photo shape',
              style: Theme.of(
                sheetContext,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ListTile(
              key: const Key('create-post-square-ratio'),
              leading: const Icon(Icons.crop_square_rounded),
              title: const Text('Square 1:1'),
              onTap: () =>
                  Navigator.pop(sheetContext, SocialPostAspectRatio.square),
            ),
            ListTile(
              key: const Key('create-post-portrait-ratio'),
              leading: const Icon(Icons.crop_portrait_rounded),
              title: const Text('Portrait 4:5'),
              onTap: () =>
                  Navigator.pop(sheetContext, SocialPostAspectRatio.portrait),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showPreparationFeedback(
  BuildContext context,
  SocialPostMediaPreparationResult result,
) {
  if (result.oversizedFailureCount > 0) {
    AppFeedback.show(
      context,
      message:
          "This photo is too large. We couldn't reduce it below 10 MB. Please choose another photo.",
      tone: AppFeedbackTone.error,
    );
  } else if (result.failureCount > 0) {
    AppFeedback.show(
      context,
      message: result.failureCount == 1
          ? 'One photo could not be prepared. Please choose another photo.'
          : '${result.failureCount} photos could not be prepared.',
      tone: AppFeedbackTone.error,
    );
  } else if (result.cropCancellationCount > 0) {
    AppFeedback.show(
      context,
      message: result.images.isEmpty
          ? 'Image cropping was cancelled.'
          : '${result.cropCancellationCount} photo(s) were skipped.',
      tone: AppFeedbackTone.info,
    );
  } else if (result.selectionTruncated) {
    AppFeedback.show(
      context,
      message: 'Only the first 5 images can be added right now.',
      tone: AppFeedbackTone.info,
    );
  }
}
