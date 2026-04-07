import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  String _activeExperimentId = 'default_onboarding';
  String _activeVariantId = 'control';

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  Future<void> logScreenView({
    required String screenName,
    required String screenClass,
  }) {
    return _analytics.logScreenView(
      screenName: screenName,
      screenClass: screenClass,
    );
  }

  Future<void> setOnboardingExperiment({
    required String experimentId,
    required String variantId,
  }) async {
    _activeExperimentId = experimentId;
    _activeVariantId = variantId;

    await _analytics.setUserProperty(
      name: 'onboarding_experiment',
      value: experimentId,
    );
    await _analytics.setUserProperty(
      name: 'onboarding_variant',
      value: variantId,
    );
    await _analytics.logEvent(
      name: 'experiment_exposure',
      parameters: {
        'experiment_id': experimentId,
        'variant_id': variantId,
        'surface': 'onboarding',
      },
    );
  }

  Future<void> logOnboardingStepViewed({
    required int stepIndex,
    required int totalSteps,
    required String title,
  }) {
    return _analytics.logEvent(
      name: 'onboarding_step_viewed',
      parameters: {
        'step_index': stepIndex,
        'step_number': stepIndex + 1,
        'total_steps': totalSteps,
        'step_title': title,
        'experiment_id': _activeExperimentId,
        'variant_id': _activeVariantId,
      },
    );
  }

  Future<void> logOnboardingAction({
    required String action,
    required int stepIndex,
    required int totalSteps,
  }) {
    return _analytics.logEvent(
      name: 'onboarding_action',
      parameters: {
        'action': action,
        'step_index': stepIndex,
        'step_number': stepIndex + 1,
        'total_steps': totalSteps,
        'experiment_id': _activeExperimentId,
        'variant_id': _activeVariantId,
      },
    );
  }

  Future<void> logSignUpViewed() {
    return logScreenView(screenName: 'signup', screenClass: 'SignupScreen');
  }

  Future<void> logSignUpAttempt({required String method}) {
    return _analytics.logSignUp(signUpMethod: method);
  }

  Future<void> logSignUpResult({
    required String method,
    required bool isSuccess,
    String? errorCode,
  }) {
    return _analytics.logEvent(
      name: 'sign_up_result',
      parameters: {
        'method': method,
        'result': isSuccess ? 'success' : 'failure',
        'error_code': errorCode ?? 'none',
        'experiment_id': _activeExperimentId,
        'variant_id': _activeVariantId,
      },
    );
  }

  Future<void> logProfileTypeView() {
    return logScreenView(
      screenName: 'profile_type',
      screenClass: 'ProfileTypeScreen',
    );
  }

  Future<void> logProfileTypeSelected({required String profileType}) async {
    await _analytics.setUserProperty(
      name: 'selected_profile_type',
      value: profileType,
    );
    await _analytics.logEvent(
      name: 'profile_type_selected',
      parameters: {
        'profile_type': profileType,
        'experiment_id': _activeExperimentId,
        'variant_id': _activeVariantId,
      },
    );
  }

  Future<void> logProfileDetailsView({required String profileType}) {
    return _analytics.logEvent(
      name: 'profile_details_viewed',
      parameters: {
        'profile_type': profileType,
        'experiment_id': _activeExperimentId,
        'variant_id': _activeVariantId,
      },
    );
  }

  Future<void> logProfileCompleted({required String profileType}) {
    return _analytics.logEvent(
      name: 'profile_completed',
      parameters: {
        'profile_type': profileType,
        'experiment_id': _activeExperimentId,
        'variant_id': _activeVariantId,
      },
    );
  }

  @visibleForTesting
  String get activeVariantId => _activeVariantId;
}
