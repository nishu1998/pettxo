import 'package:flutter/foundation.dart';

const String kDefaultAndroidUpdateMessage =
    'A new Pettxo experience is available.';
const String kOfficialPettxoPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.pettexo.app';

@immutable
class AppUpdatePolicy {
  const AppUpdatePolicy({
    required this.minimumBuild,
    required this.latestBuild,
    required this.forceUpdate,
    required this.message,
    required this.storeUrl,
    required this.isValid,
  });

  const AppUpdatePolicy.safeDefault()
    : minimumBuild = 0,
      latestBuild = 0,
      forceUpdate = false,
      message = kDefaultAndroidUpdateMessage,
      storeUrl = kOfficialPettxoPlayStoreUrl,
      isValid = true;

  final int minimumBuild;
  final int latestBuild;
  final bool forceUpdate;
  final String message;
  final String storeUrl;
  final bool isValid;

  bool blocksBuild(int installedBuild) =>
      isValid &&
      forceUpdate &&
      minimumBuild > 0 &&
      installedBuild >= 0 &&
      installedBuild < minimumBuild;

  static AppUpdatePolicy fromValues({
    required int minimumBuild,
    required int latestBuild,
    required bool forceUpdate,
    required String message,
    required String storeUrl,
  }) {
    final parsedStoreUrl = Uri.tryParse(storeUrl.trim());
    final validStoreUrl =
        parsedStoreUrl != null &&
        parsedStoreUrl.scheme == 'https' &&
        parsedStoreUrl.host == 'play.google.com';
    final valid =
        minimumBuild >= 0 &&
        latestBuild >= 0 &&
        (!forceUpdate || minimumBuild > 0);
    return AppUpdatePolicy(
      minimumBuild: minimumBuild,
      latestBuild: latestBuild,
      forceUpdate: forceUpdate,
      message: message.trim().isEmpty
          ? kDefaultAndroidUpdateMessage
          : message.trim(),
      storeUrl: validStoreUrl ? storeUrl.trim() : kOfficialPettxoPlayStoreUrl,
      isValid: valid,
    );
  }
}
