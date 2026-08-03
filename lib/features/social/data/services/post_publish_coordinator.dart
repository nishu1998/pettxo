import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/app_loader.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../domain/models/social_post_model.dart';
import '../social_post_repository.dart';

enum PostPublishPhase {
  idle,
  preparing,
  uploading,
  finalizing,
  success,
  failure,
}

@immutable
class PostPublishDraft {
  const PostPublishDraft({
    required this.imagePaths,
    required this.aspectRatio,
    required this.caption,
    required this.hashtags,
  });

  final List<String> imagePaths;
  final SocialPostAspectRatio aspectRatio;
  final String caption;
  final List<String> hashtags;

  List<XFile> toImages() =>
      imagePaths.map((path) => XFile(path)).toList(growable: false);
}

@immutable
class PostPublishState {
  const PostPublishState({
    required this.phase,
    required this.progress,
    required this.message,
    required this.eventId,
    this.post,
    this.errorMessage,
    this.recoverableDraft,
  });

  const PostPublishState.idle()
    : this(phase: PostPublishPhase.idle, progress: 0, message: '', eventId: 0);

  final PostPublishPhase phase;
  final double progress;
  final String message;
  final int eventId;
  final SocialPostModel? post;
  final String? errorMessage;
  final PostPublishDraft? recoverableDraft;

  bool get isActive =>
      phase == PostPublishPhase.preparing ||
      phase == PostPublishPhase.uploading ||
      phase == PostPublishPhase.finalizing;

  PostPublishState copyWith({
    PostPublishPhase? phase,
    double? progress,
    String? message,
    int? eventId,
    Object? post = _sentinel,
    Object? errorMessage = _sentinel,
    Object? recoverableDraft = _sentinel,
  }) {
    return PostPublishState(
      phase: phase ?? this.phase,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      eventId: eventId ?? this.eventId,
      post: identical(post, _sentinel) ? this.post : post as SocialPostModel?,
      errorMessage: identical(errorMessage, _sentinel)
          ? this.errorMessage
          : errorMessage as String?,
      recoverableDraft: identical(recoverableDraft, _sentinel)
          ? this.recoverableDraft
          : recoverableDraft as PostPublishDraft?,
    );
  }
}

class PostPublishCoordinator {
  PostPublishCoordinator._();

  static final PostPublishCoordinator instance = PostPublishCoordinator._();

  final SocialPostRepository _repository = SocialPostRepository();
  final ValueNotifier<PostPublishState> stateListenable =
      ValueNotifier<PostPublishState>(const PostPublishState.idle());

  int _eventCounter = 0;

  PostPublishState get state => stateListenable.value;

  PostPublishDraft? peekRecoverableDraft() => state.recoverableDraft;

  bool get isPublishing => state.isActive;

  PostPublishDraft? takeRecoverableDraft() {
    final draft = state.recoverableDraft;
    if (draft == null) return null;
    stateListenable.value = state.copyWith(recoverableDraft: null);
    return draft;
  }

  void clearRecoverableDraft() {
    if (state.recoverableDraft == null) return;
    stateListenable.value = state.copyWith(recoverableDraft: null);
  }

  bool startPublish({
    required List<XFile> images,
    required SocialPostAspectRatio aspectRatio,
    required String caption,
    required List<String> hashtags,
  }) {
    if (isPublishing) {
      _showInfo('A post is already being published. Please wait a moment.');
      return false;
    }

    final draft = PostPublishDraft(
      imagePaths: images.map((image) => image.path).toList(growable: false),
      aspectRatio: aspectRatio,
      caption: caption.trim(),
      hashtags: List<String>.from(hashtags),
    );

    final eventId = ++_eventCounter;
    stateListenable.value = PostPublishState(
      phase: PostPublishPhase.preparing,
      progress: 0.04,
      message: 'Preparing your post...',
      eventId: eventId,
      recoverableDraft: draft,
    );

    unawaited(_runPublish(eventId: eventId, draft: draft));
    return true;
  }

  Future<void> _runPublish({
    required int eventId,
    required PostPublishDraft draft,
  }) async {
    try {
      final post = await _repository.createPost(
        images: draft.toImages(),
        aspectRatio: draft.aspectRatio,
        caption: draft.caption,
        hashtags: draft.hashtags,
        onProgress: (progress) {
          if (state.eventId != eventId) return;
          stateListenable.value = state.copyWith(
            phase: _mapProgressPhase(progress.stage),
            progress: progress.fraction,
            message: progress.message,
          );
        },
      );

      if (state.eventId != eventId) return;
      stateListenable.value = state.copyWith(
        phase: PostPublishPhase.success,
        progress: 1,
        message: 'Post shared successfully.',
        post: post,
        errorMessage: null,
        recoverableDraft: null,
      );
      _showSuccess('Post shared successfully.');
    } catch (error, stackTrace) {
      debugPrint('PostPublishCoordinator publish failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (state.eventId != eventId) return;
      final message = _friendlyErrorMessage(error);
      stateListenable.value = state.copyWith(
        phase: PostPublishPhase.failure,
        progress: 0,
        message: message,
        errorMessage: message,
        recoverableDraft: draft,
      );
      _showError(message);
    }
  }

  PostPublishPhase _mapProgressPhase(SocialPostUploadStage stage) {
    return switch (stage) {
      SocialPostUploadStage.preparing => PostPublishPhase.preparing,
      SocialPostUploadStage.uploading => PostPublishPhase.uploading,
      SocialPostUploadStage.finalizing => PostPublishPhase.finalizing,
    };
  }

  String _friendlyErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) {
      return 'We could not publish your post right now. Your draft is still available.';
    }
    return message;
  }

  void _showSuccess(String message) {
    final context = AppLoader.navigatorKey.currentContext;
    if (context == null) return;
    AppSnackbar.showSuccess(context, message);
  }

  void _showError(String message) {
    final context = AppLoader.navigatorKey.currentContext;
    if (context == null) return;
    AppSnackbar.showError(context, message);
  }

  void _showInfo(String message) {
    final context = AppLoader.navigatorKey.currentContext;
    if (context == null) return;
    AppSnackbar.showInfo(context, message);
  }
}

const Object _sentinel = Object();
