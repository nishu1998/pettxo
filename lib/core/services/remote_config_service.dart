import 'package:firebase_remote_config/firebase_remote_config.dart';

class RemoteConfigService {
  final remoteConfig = FirebaseRemoteConfig.instance;

  Future<void> init() async {
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
}