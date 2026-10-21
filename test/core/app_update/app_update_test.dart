import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:pettexo/core/app_update/app_update_gate.dart';
import 'package:pettexo/core/app_update/app_update_policy.dart';
import 'package:pettexo/core/app_update/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppUpdatePolicy', () {
    test('blocks only builds below a valid forced minimum', () {
      final policy = policyFor(minimum: 22, force: true);
      expect(policy.blocksBuild(21), isTrue);
      expect(policy.blocksBuild(22), isFalse);
      expect(policy.blocksBuild(23), isFalse);
    });

    test('disabled force update allows an older build', () {
      expect(policyFor(minimum: 22, force: false).blocksBuild(1), isFalse);
    });

    test('invalid forced configuration fails open', () {
      expect(policyFor(minimum: 0, force: true).isValid, isFalse);
      expect(policyFor(minimum: 0, force: true).blocksBuild(1), isFalse);
    });

    test('invalid store URL falls back to the official listing', () {
      final policy = AppUpdatePolicy.fromValues(
        minimumBuild: 22,
        latestBuild: 22,
        forceUpdate: true,
        message: '',
        storeUrl: 'https://example.com/not-pettxo',
      );
      expect(policy.storeUrl, kOfficialPettxoPlayStoreUrl);
      expect(policy.message, kDefaultAndroidUpdateMessage);
    });
  });

  group('AppUpdateController', () {
    test(
      'cached mandatory policy remains enforced after refresh failure',
      () async {
        final source = FakePolicySource(policyFor(minimum: 22, force: true))
          ..refreshError = StateError('offline');
        final controller = controllerFor(source: source, installedBuild: 21);
        addTearDown(controller.dispose);

        await controller.initialize();
        expect(controller.status, AppUpdateGateStatus.blocked);
        await controller.refresh();
        expect(controller.status, AppUpdateGateStatus.blocked);
      },
    );

    test('fresh offline installation with defaults is allowed', () async {
      final source = FakePolicySource(const AppUpdatePolicy.safeDefault());
      final controller = controllerFor(source: source, installedBuild: 21);
      addTearDown(controller.dispose);

      await controller.initialize();
      expect(controller.status, AppUpdateGateStatus.allowed);
    });

    test('canceled update remains blocked', () async {
      final launcher = FakeLauncher(MandatoryUpdateActionResult.canceled);
      final controller = controllerFor(
        source: FakePolicySource(policyFor(minimum: 22, force: true)),
        installedBuild: 21,
        launcher: launcher,
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.launchUpdate();
      expect(controller.status, AppUpdateGateStatus.blocked);
      expect(controller.lastActionResult, MandatoryUpdateActionResult.canceled);
      expect(launcher.lastStoreUrl, kOfficialPettxoPlayStoreUrl);
    });

    test('failed update remains blocked', () async {
      final controller = controllerFor(
        source: FakePolicySource(policyFor(minimum: 22, force: true)),
        installedBuild: 21,
        launcher: FakeLauncher(MandatoryUpdateActionResult.failed),
      );
      addTearDown(controller.dispose);

      await controller.initialize();
      await controller.launchUpdate();
      expect(controller.status, AppUpdateGateStatus.blocked);
      expect(controller.lastActionResult, MandatoryUpdateActionResult.failed);
    });

    test(
      'resume reevaluates the installed build and removes the gate',
      () async {
        final build = FakeInstalledBuildProvider(21);
        final controller = AppUpdateController(
          policySource: FakePolicySource(policyFor(minimum: 22, force: true)),
          installedBuildProvider: build,
          updateLauncher: FakeLauncher(MandatoryUpdateActionResult.completed),
        );
        addTearDown(controller.dispose);

        await controller.initialize();
        expect(controller.status, AppUpdateGateStatus.blocked);
        build.value = 22;
        controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.status, AppUpdateGateStatus.allowed);
      },
    );
  });

  test(
    'Google Play launcher opens the configured listing when unavailable',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      Uri? openedUri;
      final launcher = GooglePlayMandatoryUpdateLauncher(
        checkForUpdate: () async =>
            playUpdateInfo(UpdateAvailability.updateNotAvailable),
        openUrl: (uri, {required mode}) async {
          openedUri = uri;
          return true;
        },
      );

      final result = await launcher.launch(kOfficialPettxoPlayStoreUrl);
      expect(result, MandatoryUpdateActionResult.storeOpened);
      expect(openedUri.toString(), kOfficialPettxoPlayStoreUrl);
    },
  );

  testWidgets('active gate blocks back navigation and covers routed content', (
    tester,
  ) async {
    final controller = controllerFor(
      source: FakePolicySource(policyFor(minimum: 22, force: true)),
      installedBuild: 21,
    );
    addTearDown(controller.dispose);
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('root')),
      ),
    );
    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => AppUpdateGate(
          controller: controller,
          child: const Scaffold(body: Text('deep linked protected content')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A Better Pettxo Awaits!'), findsOneWidget);
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('deep linked protected content'),
      findsNothing,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('A Better Pettxo Awaits!'), findsOneWidget);
    semantics.dispose();
  });
}

AppUpdateInfo playUpdateInfo(UpdateAvailability availability) => AppUpdateInfo(
  updateAvailability: availability,
  immediateUpdateAllowed: false,
  immediateAllowedPreconditions: null,
  flexibleUpdateAllowed: false,
  flexibleAllowedPreconditions: null,
  availableVersionCode: null,
  installStatus: InstallStatus.unknown,
  packageName: 'com.pettexo.app',
  clientVersionStalenessDays: null,
  updatePriority: 0,
);

AppUpdatePolicy policyFor({required int minimum, required bool force}) =>
    AppUpdatePolicy.fromValues(
      minimumBuild: minimum,
      latestBuild: minimum,
      forceUpdate: force,
      message: 'Update to continue.',
      storeUrl: kOfficialPettxoPlayStoreUrl,
    );

AppUpdateController controllerFor({
  required FakePolicySource source,
  required int installedBuild,
  FakeLauncher? launcher,
}) => AppUpdateController(
  policySource: source,
  installedBuildProvider: FakeInstalledBuildProvider(installedBuild),
  updateLauncher:
      launcher ?? FakeLauncher(MandatoryUpdateActionResult.storeOpened),
);

class FakePolicySource implements AppUpdatePolicySource {
  FakePolicySource(this.policy);

  AppUpdatePolicy policy;
  Object? refreshError;
  final updates = StreamController<void>.broadcast();

  @override
  AppUpdatePolicy get currentPolicy => policy;

  @override
  Future<void> initialize() async {}

  @override
  Stream<void> get policyUpdates => updates.stream;

  @override
  Future<void> refresh() async {
    if (refreshError case final error?) throw error;
  }
}

class FakeInstalledBuildProvider implements InstalledBuildProvider {
  FakeInstalledBuildProvider(this.value);
  int? value;

  @override
  Future<int?> installedBuild() async => value;
}

class FakeLauncher implements MandatoryUpdateLauncher {
  FakeLauncher(this.result);
  final MandatoryUpdateActionResult result;
  String? lastStoreUrl;

  @override
  Future<MandatoryUpdateActionResult> launch(String storeUrl) async {
    lastStoreUrl = storeUrl;
    return result;
  }

  @override
  Future<MandatoryUpdateActionResult?> resumeInterrupted(
    String storeUrl,
  ) async => null;
}
