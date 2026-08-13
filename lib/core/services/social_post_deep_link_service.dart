import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/auth/data/services/auth_onboarding_service.dart';
import '../../features/auth/domain/utils/auth_onboarding_resolver.dart';
import '../../features/profile/presentation/widgets/profile_content_sections.dart';
import '../utils/social_post_share.dart';
import 'app_loader.dart';

class SocialPostDeepLinkService {
  SocialPostDeepLinkService._();

  static final SocialPostDeepLinkService instance =
      SocialPostDeepLinkService._();

  static const MethodChannel _methodChannel = MethodChannel(
    'com.pettexo.app/social_post_deep_links',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.pettexo.app/social_post_deep_links/events',
  );
  static const Duration _startupNavigationDelay = Duration(milliseconds: 2200);

  String? _pendingPostId;
  DateTime? _pendingPostReceivedAt;
  DateTime _serviceStartedAt = DateTime.now();
  bool _initialized = false;
  bool _isNavigating = false;
  final AuthOnboardingService _authOnboardingService = AuthOnboardingService();

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _serviceStartedAt = DateTime.now();

    FirebaseAuth.instance.authStateChanges().listen((_) {
      unawaited(_attemptPendingNavigation());
    });

    _eventChannel
        .receiveBroadcastStream()
        .map((event) => event as String?)
        .listen((link) {
          _handleIncomingLink(link, treatAsInitialLink: false);
        });

    final initialLink = await _methodChannel.invokeMethod<String>(
      'getInitialLink',
    );
    _handleIncomingLink(initialLink, treatAsInitialLink: true);
  }

  void _handleIncomingLink(
    String? rawLink, {
    required bool treatAsInitialLink,
  }) {
    final normalized = rawLink?.trim() ?? '';
    if (normalized.isEmpty) return;
    final uri = Uri.tryParse(normalized);
    if (uri == null) return;
    final postId = tryParseSocialPostIdFromUri(uri);
    if (postId == null) return;
    _pendingPostId = postId;
    _pendingPostReceivedAt = treatAsInitialLink ? _serviceStartedAt : null;
    unawaited(_attemptPendingNavigation());
  }

  Future<void> _attemptPendingNavigation() async {
    if (_isNavigating) return;
    final postId = _pendingPostId?.trim() ?? '';
    if (postId.isEmpty) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    AuthOnboardingResolution resolution;
    try {
      resolution = await _authOnboardingService.resolveCurrentState();
    } catch (_) {
      return;
    }
    if (resolution.state != AuthOnboardingState.authenticated) {
      return;
    }

    final navigator = AppLoader.navigatorKey.currentState;
    if (navigator == null || AppLoader.navigatorKey.currentContext == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_attemptPendingNavigation());
      });
      return;
    }

    final pendingReceivedAt = _pendingPostReceivedAt;
    if (pendingReceivedAt != null) {
      final readyAt = pendingReceivedAt.add(_startupNavigationDelay);
      final remaining = readyAt.difference(DateTime.now());
      if (remaining.inMicroseconds > 0) {
        await Future<void>.delayed(remaining);
        if (_pendingPostId?.trim() != postId) return;
      }
    }

    _isNavigating = true;
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      navigator.push(
        MaterialPageRoute(
          builder: (_) => ProfilePostDetailScreen.fromPostId(
            authorId: '',
            initialPostId: postId,
            currentUserId: currentUserId,
          ),
        ),
      );
      if (_pendingPostId?.trim() == postId) {
        _pendingPostId = null;
        _pendingPostReceivedAt = null;
      }
    } finally {
      _isNavigating = false;
    }
  }
}
