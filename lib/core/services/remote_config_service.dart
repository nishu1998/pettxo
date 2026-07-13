import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

class RemoteConfigService {
  final remoteConfig = FirebaseRemoteConfig.instance;

  static const Map<String, Object> _defaults = {
    'tagline_1': 'Premium pet experience',
    'title_1': 'Connect & Explore Pets',
    'subtitle_1': 'Join a community of pet lovers and share moments.',
    'tagline_2': 'Trusted care, easier',
    'title_2': 'Book Trusted Services',
    'subtitle_2': 'Find vets, groomers and trainers easily.',
    'tagline_3': 'Discover what’s nearby',
    'title_3': 'Everything Nearby',
    'subtitle_3': 'Discover pet-friendly places around you.',
    'onboarding_experiment_id': 'default_onboarding',
    'onboarding_variant_id': 'control',
    'onboarding_display_version': 1,
    'onboarding_force_show': false,
  };

  Future<void> init() async {
    try {
      await remoteConfig.setDefaults(_defaults);
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 2),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await remoteConfig.fetchAndActivate();
    } catch (error) {
      debugPrint('RemoteConfigService init debug -> using defaults: $error');
    }
  }

  String getString(String key, String fallback) {
    try {
      final value = remoteConfig.getString(key);
      return value.isEmpty ? fallback : value;
    } catch (_) {
      return fallback;
    }
  }

  String get onboardingExperimentId =>
      getString('onboarding_experiment_id', 'default_onboarding');

  String get onboardingVariantId =>
      getString('onboarding_variant_id', 'control');

  int get onboardingDisplayVersion => _readInt('onboarding_display_version', 1);

  bool get onboardingForceShow => _readBool('onboarding_force_show', false);

  int _readInt(String key, int fallback) {
    try {
      return remoteConfig.getInt(key);
    } catch (_) {
      return fallback;
    }
  }

  bool _readBool(String key, bool fallback) {
    try {
      return remoteConfig.getBool(key);
    } catch (_) {
      return fallback;
    }
  }
}
