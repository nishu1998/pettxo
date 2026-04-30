import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/app_loader.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../domain/models/user_restriction_state.dart';

class UserRestrictionService {
  UserRestrictionService._();

  static final UserRestrictionService instance = UserRestrictionService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final AuthService _authService = AuthService();
  final ProfileRepository _profileRepository = ProfileRepository();
  final ValueNotifier<UserRestrictionState> _stateNotifier = ValueNotifier(
    UserRestrictionState.unrestricted,
  );

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<UserRestrictionState>? _restrictionSubscription;
  bool _isHandlingHardBan = false;

  ValueListenable<UserRestrictionState> get stateListenable => _stateNotifier;

  UserRestrictionState get currentState => _stateNotifier.value;

  Future<void> initialize() async {
    await _authSubscription?.cancel();
    _authSubscription = _auth.authStateChanges().listen(_handleAuthStateChange);
    await _handleAuthStateChange(_auth.currentUser);
  }

  Future<void> _handleAuthStateChange(User? user) async {
    await _restrictionSubscription?.cancel();
    _restrictionSubscription = null;

    if (user == null) {
      _stateNotifier.value = UserRestrictionState.unrestricted;
      _isHandlingHardBan = false;
      return;
    }

    _restrictionSubscription = _profileRepository
        .watchCurrentUserRestrictionState()
        .listen(
          (state) async {
            _stateNotifier.value = state;
            if (state.isHardBanned) {
              await _handleHardBan();
            }
          },
          onError: (_) {
            _stateNotifier.value = UserRestrictionState.unrestricted;
          },
        );
  }

  Future<void> _handleHardBan() async {
    if (_isHandlingHardBan) return;
    _isHandlingHardBan = true;

    try {
      if (_auth.currentUser != null) {
        await _authService.logout();
      }

      final navigator = AppLoader.navigatorKey.currentState;
      navigator?.pushNamedAndRemoveUntil('/signin', (route) => false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = AppLoader.navigatorKey.currentContext;
        if (context == null) return;
        AppFeedback.show(
          context,
          message: UserRestrictionState.hardBanMessage,
          tone: AppFeedbackTone.error,
        );
      });
    } finally {
      _stateNotifier.value = UserRestrictionState.unrestricted;
      _isHandlingHardBan = false;
    }
  }

  bool ensureCanUseSocialFeatures(BuildContext context) {
    final state = currentState;
    if (state.isHardBanned) {
      AppFeedback.show(
        context,
        message: UserRestrictionState.hardBanMessage,
        tone: AppFeedbackTone.error,
      );
      unawaited(_handleHardBan());
      return false;
    }
    if (!state.canUseSocialFeatures) {
      AppFeedback.show(
        context,
        message: UserRestrictionState.socialBanMessage,
        tone: AppFeedbackTone.warning,
      );
      return false;
    }
    return true;
  }

  bool ensureCanUseBookingFeatures(BuildContext context) {
    final state = currentState;
    if (state.isHardBanned) {
      AppFeedback.show(
        context,
        message: UserRestrictionState.hardBanMessage,
        tone: AppFeedbackTone.error,
      );
      unawaited(_handleHardBan());
      return false;
    }
    if (!state.canUseBookingFeatures) {
      AppFeedback.show(
        context,
        message: UserRestrictionState.bookingBanMessage,
        tone: AppFeedbackTone.warning,
      );
      return false;
    }
    return true;
  }
}
