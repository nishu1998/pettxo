import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigService {
  final remoteConfig = FirebaseRemoteConfig.instance;

  Future<void> init() async {
    await remoteConfig.setDefaults(const {
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
    });

    await remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 2),
        minimumFetchInterval: const Duration(hours: 1),
      ),
    );

    await remoteConfig.fetchAndActivate();
  }

  String getString(String key, String fallback) {
    return remoteConfig.getString(key).isEmpty
        ? fallback
        : remoteConfig.getString(key);
  }

  String get onboardingExperimentId =>
      getString('onboarding_experiment_id', 'default_onboarding');

  String get onboardingVariantId =>
      getString('onboarding_variant_id', 'control');
}
