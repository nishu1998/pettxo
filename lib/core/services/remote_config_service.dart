import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

@immutable
class PlayStoreReviewConfig {
  const PlayStoreReviewConfig({
    required this.enabled,
    required this.cooldownDays,
    required this.maxRequests,
    required this.fallbackAppOpens,
    required this.promptDelay,
  });

  final bool enabled;
  final int cooldownDays;
  final int maxRequests;
  final int fallbackAppOpens;
  final Duration promptDelay;
}

class RemoteConfigService {
  RemoteConfigService();

  final remoteConfig = FirebaseRemoteConfig.instance;
  static bool _initialized = false;
  static Future<void>? _initFuture;

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
    'play_store_review_enabled': true,
    'play_store_review_cooldown_days': 30,
    'play_store_review_max_requests': 2,
    'play_store_review_fallback_app_opens': 15,
    'play_store_review_prompt_delay_seconds': 7,
  };

  Future<void> init() async {
    if (_initialized) return;
    final pending = _initFuture;
    if (pending != null) {
      await pending;
      return;
    }
    _initFuture = _runInit();
    await _initFuture;
  }

  Future<void> _runInit() async {
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
    } finally {
      _initialized = true;
      _initFuture = null;
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

  PlayStoreReviewConfig get playStoreReviewConfig {
    final config = PlayStoreReviewConfig(
      enabled: _readBool('play_store_review_enabled', true),
      cooldownDays: _readBoundedInt(
        'play_store_review_cooldown_days',
        fallback: 30,
        min: 1,
        max: 365,
      ),
      maxRequests: _readBoundedInt(
        'play_store_review_max_requests',
        fallback: 2,
        min: 0,
        max: 5,
      ),
      fallbackAppOpens: _readBoundedInt(
        'play_store_review_fallback_app_opens',
        fallback: 15,
        min: 1,
        max: 100,
      ),
      promptDelay: Duration(
        seconds: _readBoundedInt(
          'play_store_review_prompt_delay_seconds',
          fallback: 7,
          min: 0,
          max: 30,
        ),
      ),
    );
    if (kDebugMode) {
      debugPrint(
        'RemoteConfigService play review debug -> enabled=${config.enabled} cooldownDays=${config.cooldownDays} maxRequests=${config.maxRequests} fallbackAppOpens=${config.fallbackAppOpens} promptDelaySeconds=${config.promptDelay.inSeconds}',
      );
    }
    return config;
  }

  int _readInt(String key, int fallback) {
    try {
      return remoteConfig.getInt(key);
    } catch (_) {
      return fallback;
    }
  }

  int _readBoundedInt(
    String key, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final value = _readInt(key, fallback);
    if (value < min || value > max) {
      return fallback;
    }
    return value;
  }

  bool _readBool(String key, bool fallback) {
    try {
      return remoteConfig.getBool(key);
    } catch (_) {
      return fallback;
    }
  }
}
