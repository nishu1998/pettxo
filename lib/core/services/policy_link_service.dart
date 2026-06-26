import 'package:flutter/material.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:url_launcher/url_launcher.dart';

class PolicyLinkService {
  const PolicyLinkService._();

  static final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;
  static bool _initialized = false;

  static const String cancellationPolicyKey = 'cancellation_policy_url';
  static const String refundPolicyKey = 'refund_policy_url';
  static const String termsConditionsKey = 'terms_conditions_url';
  static const String privacyPolicyKey = 'privacy_policy_url';
  static const String providerPolicyKey = 'provider_policy_url';

  static const Map<String, String> _defaultUrls = {
    cancellationPolicyKey: 'https://pettxo.com/cancellation-policy',
    refundPolicyKey: 'https://pettxo.com/refund-policy',
    termsConditionsKey: 'https://pettxo.com/terms-and-conditions',
    privacyPolicyKey: 'https://pettxo.com/privacy-policy',
    providerPolicyKey: 'https://pettxo.com/provider-policy',
  };

  static Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _remoteConfig.setDefaults(_defaultUrls);
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 2),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await _remoteConfig.fetchAndActivate();
    } catch (_) {
      // Keep default URLs when Remote Config is unavailable.
    } finally {
      _initialized = true;
    }
  }

  static String urlForKey(String key) {
    final fallback = _defaultUrls[key] ?? '';
    try {
      final value = _remoteConfig.getString(key).trim();
      return value.isEmpty ? fallback : value;
    } catch (_) {
      return fallback;
    }
  }

  static Future<bool> openExternalPolicyUrl(String key) async {
    final uri = Uri.tryParse(urlForKey(key));
    if (uri == null) return false;

    try {
      final canLaunch = await canLaunchUrl(uri);
      if (!canLaunch) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static Future<void> openPolicy(
    BuildContext context, {
    required String webUrl,
    required String fallbackRoute,
  }) async {
    final uri = Uri.tryParse(webUrl);

    if (uri != null) {
      try {
        final canLaunch = await canLaunchUrl(uri);
        if (canLaunch) {
          final openedInApp = await launchUrl(
            uri,
            mode: LaunchMode.inAppBrowserView,
          );
          if (openedInApp) return;

          final openedExternal = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (openedExternal) return;
        }
      } catch (_) {
        // Fall back to the in-app policy screen when browser launch fails.
      }
    }

    if (!context.mounted) return;
    await Navigator.pushNamed(context, fallbackRoute);
  }
}
