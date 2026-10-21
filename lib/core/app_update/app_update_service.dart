import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/remote_config_service.dart';
import 'app_update_policy.dart';

abstract interface class AppUpdatePolicySource {
  Future<void> initialize();
  Future<void> refresh();
  AppUpdatePolicy get currentPolicy;
  Stream<void> get policyUpdates;
}

class FirebaseAppUpdatePolicySource implements AppUpdatePolicySource {
  FirebaseAppUpdatePolicySource({RemoteConfigService? remoteConfigService})
    : _remoteConfigService = remoteConfigService ?? RemoteConfigService();

  final RemoteConfigService _remoteConfigService;

  @override
  Future<void> initialize() => _remoteConfigService.init();

  @override
  Future<void> refresh() async {
    try {
      await _remoteConfigService.refresh();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('App update policy refresh failed; using activated values.');
      }
    }
  }

  @override
  AppUpdatePolicy get currentPolicy => AppUpdatePolicy.fromValues(
    minimumBuild: _remoteConfigService.remoteConfig.getInt('android_min_build'),
    latestBuild: _remoteConfigService.remoteConfig.getInt(
      'android_latest_build',
    ),
    forceUpdate: _remoteConfigService.remoteConfig.getBool(
      'android_force_update',
    ),
    message: _remoteConfigService.getString(
      'android_update_message',
      kDefaultAndroidUpdateMessage,
    ),
    storeUrl: _remoteConfigService.getString(
      'android_store_url',
      kOfficialPettxoPlayStoreUrl,
    ),
  );

  @override
  Stream<void> get policyUpdates => _remoteConfigService.configUpdates
      .asyncMap((_) => _remoteConfigService.remoteConfig.activate())
      .map((_) {});
}

abstract interface class InstalledBuildProvider {
  Future<int?> installedBuild();
}

class PackageInfoInstalledBuildProvider implements InstalledBuildProvider {
  @override
  Future<int?> installedBuild() async {
    final raw = (await PackageInfo.fromPlatform()).buildNumber.trim();
    return int.tryParse(raw);
  }
}

enum MandatoryUpdateActionResult {
  completed,
  canceled,
  failed,
  storeOpened,
  storeFailed,
  noUpdateAvailable,
  alreadyInFlight,
}

abstract interface class MandatoryUpdateLauncher {
  Future<MandatoryUpdateActionResult> launch(String storeUrl);
  Future<MandatoryUpdateActionResult?> resumeInterrupted(String storeUrl);
}

class GooglePlayMandatoryUpdateLauncher implements MandatoryUpdateLauncher {
  GooglePlayMandatoryUpdateLauncher({
    Future<AppUpdateInfo> Function()? checkForUpdate,
    Future<AppUpdateResult> Function()? performImmediateUpdate,
    Future<bool> Function(Uri uri, {required LaunchMode mode})? openUrl,
  }) : _checkForUpdate = checkForUpdate ?? InAppUpdate.checkForUpdate,
       _performImmediate =
           performImmediateUpdate ?? InAppUpdate.performImmediateUpdate,
       _openUrl = openUrl ?? launchUrl;

  final Future<AppUpdateInfo> Function() _checkForUpdate;
  final Future<AppUpdateResult> Function() _performImmediate;
  final Future<bool> Function(Uri uri, {required LaunchMode mode}) _openUrl;
  bool _operationInFlight = false;
  bool _resumeAttemptedForCurrentForeground = false;

  @override
  Future<MandatoryUpdateActionResult> launch(String storeUrl) =>
      _guarded(() async {
        if (defaultTargetPlatform != TargetPlatform.android) {
          return _openStore(storeUrl);
        }
        try {
          final info = await _checkForUpdate();
          final updateAvailable =
              info.updateAvailability == UpdateAvailability.updateAvailable ||
              info.updateAvailability ==
                  UpdateAvailability.developerTriggeredUpdateInProgress;
          if (updateAvailable && info.immediateUpdateAllowed) {
            return _performImmediateUpdate();
          }
          final fallback = await _openStore(storeUrl);
          return fallback == MandatoryUpdateActionResult.storeOpened
              ? fallback
              : MandatoryUpdateActionResult.noUpdateAvailable;
        } catch (_) {
          return _openStore(storeUrl);
        }
      });

  @override
  Future<MandatoryUpdateActionResult?> resumeInterrupted(
    String storeUrl,
  ) async {
    if (defaultTargetPlatform != TargetPlatform.android ||
        _resumeAttemptedForCurrentForeground) {
      return null;
    }
    _resumeAttemptedForCurrentForeground = true;
    final result = await _guarded(() async {
      try {
        final info = await _checkForUpdate();
        if (info.updateAvailability ==
                UpdateAvailability.developerTriggeredUpdateInProgress &&
            info.immediateUpdateAllowed) {
          return _performImmediateUpdate();
        }
      } catch (_) {
        // The mandatory screen remains active and offers the store fallback.
      }
      return MandatoryUpdateActionResult.noUpdateAvailable;
    });
    return result;
  }

  void markBackgrounded() {
    _resumeAttemptedForCurrentForeground = false;
  }

  Future<MandatoryUpdateActionResult> _performImmediateUpdate() async {
    try {
      final result = await _performImmediate();
      return switch (result) {
        AppUpdateResult.success => MandatoryUpdateActionResult.completed,
        AppUpdateResult.userDeniedUpdate =>
          MandatoryUpdateActionResult.canceled,
        AppUpdateResult.inAppUpdateFailed => MandatoryUpdateActionResult.failed,
      };
    } catch (_) {
      return MandatoryUpdateActionResult.failed;
    }
  }

  Future<MandatoryUpdateActionResult> _openStore(String storeUrl) async {
    final uri =
        Uri.tryParse(storeUrl) ?? Uri.parse(kOfficialPettxoPlayStoreUrl);
    try {
      final opened = await _openUrl(uri, mode: LaunchMode.externalApplication);
      return opened
          ? MandatoryUpdateActionResult.storeOpened
          : MandatoryUpdateActionResult.storeFailed;
    } catch (_) {
      return MandatoryUpdateActionResult.storeFailed;
    }
  }

  Future<MandatoryUpdateActionResult> _guarded(
    Future<MandatoryUpdateActionResult> Function() operation,
  ) async {
    if (_operationInFlight) {
      return MandatoryUpdateActionResult.alreadyInFlight;
    }
    _operationInFlight = true;
    try {
      return await operation();
    } finally {
      _operationInFlight = false;
    }
  }
}

enum AppUpdateGateStatus { checking, allowed, blocked }

class AppUpdateController extends ChangeNotifier with WidgetsBindingObserver {
  AppUpdateController({
    required AppUpdatePolicySource policySource,
    required InstalledBuildProvider installedBuildProvider,
    required MandatoryUpdateLauncher updateLauncher,
  }) : _policySource = policySource,
       _installedBuildProvider = installedBuildProvider,
       _updateLauncher = updateLauncher;

  factory AppUpdateController.production() => AppUpdateController(
    policySource: FirebaseAppUpdatePolicySource(),
    installedBuildProvider: PackageInfoInstalledBuildProvider(),
    updateLauncher: GooglePlayMandatoryUpdateLauncher(),
  );

  final AppUpdatePolicySource _policySource;
  final InstalledBuildProvider _installedBuildProvider;
  final MandatoryUpdateLauncher _updateLauncher;
  StreamSubscription<void>? _policySubscription;
  AppUpdateGateStatus status = AppUpdateGateStatus.checking;
  AppUpdatePolicy policy = const AppUpdatePolicy.safeDefault();
  MandatoryUpdateActionResult? lastActionResult;
  bool actionInProgress = false;
  bool _disposed = false;

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    try {
      await _policySource.initialize();
    } catch (_) {
      // Activated values (or safe defaults on a first install) remain readable.
    }
    try {
      await _evaluate();
    } catch (_) {
      status = AppUpdateGateStatus.allowed;
      _notify();
    }
    try {
      _policySubscription = _policySource.policyUpdates.listen((_) {
        unawaited(_evaluate());
      });
    } catch (_) {
      // Real-time Remote Config is an optimization; startup/resume still fetch.
    }
  }

  Future<void> refresh() async {
    try {
      await _policySource.refresh();
    } catch (_) {
      // Keep enforcing the last activated policy when the network is offline.
    } finally {
      await _evaluate();
    }
  }

  Future<void> launchUpdate() async {
    if (status != AppUpdateGateStatus.blocked || actionInProgress) return;
    actionInProgress = true;
    lastActionResult = null;
    _notify();
    lastActionResult = await _updateLauncher.launch(policy.storeUrl);
    actionInProgress = false;
    await refresh();
  }

  Future<void> _evaluate() async {
    final installedBuild = await _installedBuildProvider.installedBuild();
    policy = _policySource.currentPolicy;
    status = installedBuild != null && policy.blocksBuild(installedBuild)
        ? AppUpdateGateStatus.blocked
        : AppUpdateGateStatus.allowed;
    _notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_handleResume());
    } else if (_updateLauncher is GooglePlayMandatoryUpdateLauncher) {
      _updateLauncher.markBackgrounded();
    }
  }

  Future<void> _handleResume() async {
    await refresh();
    if (status == AppUpdateGateStatus.blocked) {
      lastActionResult = await _updateLauncher.resumeInterrupted(
        policy.storeUrl,
      );
      if (lastActionResult == MandatoryUpdateActionResult.completed) {
        await refresh();
      }
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_policySubscription?.cancel());
    super.dispose();
  }
}
