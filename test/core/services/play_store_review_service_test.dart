import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/services/app_loader.dart';
import 'package:pettexo/core/services/play_store_review_service.dart';
import 'package:pettexo/core/services/remote_config_service.dart';
import 'package:pettexo/features/social/data/services/post_publish_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayStoreReviewService', () {
    late _FakeAuthSession authSession;
    late _MemoryPlayStoreReviewStateStore stateStore;
    late _FakePlayReviewLauncher launcher;
    late _FakeCompletedBookingStreamSource bookingStreamSource;
    late _FakeSocialPostCounter socialPostCounter;
    late _FakePlayStoreReviewConfigProvider configProvider;
    late ValueNotifier<PostPublishState> postPublishStateListenable;
    late DateTime now;
    late List<PlayStoreReviewDialogAction?> dialogActions;
    late int dialogCount;

    PlayStoreReviewService buildService({
      PlayStoreReviewDelayScheduler? delayScheduler,
    }) {
      return PlayStoreReviewService(
        authSession: authSession,
        stateStore: stateStore,
        reviewLauncher: launcher,
        completedBookingStreamSource: bookingStreamSource,
        socialPostCounter: socialPostCounter,
        configProvider: configProvider,
        postPublishStateListenable: postPublishStateListenable,
        delayScheduler: delayScheduler ?? ((_) async {}),
        dialogPresenter: (context) async {
          dialogCount += 1;
          if (dialogActions.isEmpty) return null;
          return dialogActions.removeAt(0);
        },
        now: () => now,
      );
    }

    setUp(() {
      authSession = _FakeAuthSession();
      stateStore = _MemoryPlayStoreReviewStateStore(() => now);
      launcher = _FakePlayReviewLauncher();
      bookingStreamSource = _FakeCompletedBookingStreamSource();
      socialPostCounter = _FakeSocialPostCounter();
      configProvider = _FakePlayStoreReviewConfigProvider();
      postPublishStateListenable = ValueNotifier<PostPublishState>(
        const PostPublishState.idle(),
      );
      now = DateTime(2026, 8, 8, 12);
      dialogActions = <PlayStoreReviewDialogAction?>[];
      dialogCount = 0;
    });

    tearDown(() {
      postPublishStateListenable.dispose();
    });

    Future<void> pumpHost(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: AppLoader.navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      await tester.pump();
    }

    testWidgets('customer receives eligibility after completed booking', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('customer-1');
      await tester.pump();

      dialogActions.add(PlayStoreReviewDialogAction.maybeLater);
      bookingStreamSource.emitCustomer('customer-1', 'booking-1');
      await tester.pump();

      expect(dialogCount, 1);
      expect(stateStore.stateFor('customer-1').pendingOpportunity, isTrue);
      unawaited(service.dispose());
    });

    testWidgets('provider receives eligibility after completed booking', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('provider-1');
      await tester.pump();

      dialogActions.add(PlayStoreReviewDialogAction.maybeLater);
      bookingStreamSource.emitProvider('provider-1', 'booking-7');
      await tester.pump();

      expect(dialogCount, 1);
      expect(
        stateStore.stateFor('provider-1').completedBookingMilestoneUnlocked,
        isTrue,
      );
      unawaited(service.dispose());
    });

    testWidgets('customer and provider states are independent per UID', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('customer-a');
      await tester.pump();
      bookingStreamSource.emitCustomer('customer-a', 'booking-1');
      await tester.pump();

      unawaited(service.dispose());

      final secondService = buildService();
      await secondService.initialize();
      authSession.emit('provider-b');
      await tester.pump();
      await secondService.debugEvaluatePendingOpportunity();

      expect(
        stateStore.stateFor('customer-a').completedBookingMilestoneUnlocked,
        isTrue,
      );
      expect(
        stateStore.stateFor('provider-b').completedBookingMilestoneUnlocked,
        isFalse,
      );
      unawaited(secondService.dispose());
    });

    testWidgets('one UID shares request state across milestones and roles', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('shared-user');
      await tester.pump();

      dialogActions.add(PlayStoreReviewDialogAction.rateOnPlayStore);
      bookingStreamSource.emitCustomer('shared-user', 'booking-1');
      await tester.pump();

      expect(stateStore.stateFor('shared-user').requestCount, 1);

      bookingStreamSource.emitProvider('shared-user', 'booking-2');
      await tester.pump();

      expect(
        stateStore.stateFor('shared-user').completedBookingMilestoneCount,
        2,
      );
      expect(dialogCount, 1);
      unawaited(service.dispose());
    });

    testWidgets('first successful social post does not trigger', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      socialPostCounter.counts['poster-1'] = 0;
      authSession.emit('poster-1');
      await tester.pump();

      await service.debugHandleSuccessfulPostForCurrentUser();
      await tester.pump();

      expect(dialogCount, 0);
      expect(stateStore.stateFor('poster-1').successfulPostCount, 1);
      unawaited(service.dispose());
    });

    testWidgets('second successful social post triggers eligibility', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      socialPostCounter.counts['poster-2'] = 0;
      authSession.emit('poster-2');
      await tester.pump();
      await service.debugHandleSuccessfulPostForCurrentUser();

      dialogActions.add(PlayStoreReviewDialogAction.maybeLater);
      await service.debugHandleSuccessfulPostForCurrentUser();
      await tester.pump();

      expect(dialogCount, 1);
      expect(
        stateStore.stateFor('poster-2').secondSocialPostMilestoneUnlocked,
        isTrue,
      );
      unawaited(service.dispose());
    });

    testWidgets('failed post publish state does not count', (tester) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('poster-3');
      await tester.pump();

      postPublishStateListenable.value = const PostPublishState(
        phase: PostPublishPhase.failure,
        progress: 0,
        message: 'failed',
        eventId: 77,
      );
      await tester.pump();

      expect(dialogCount, 0);
      expect(stateStore.stateFor('poster-3').successfulPostCount, 0);
      unawaited(service.dispose());
    });

    testWidgets('app opens 1 to 14 do not trigger fallback', (tester) async {
      await pumpHost(tester);

      for (var i = 0; i < 14; i += 1) {
        final service = buildService();
        await service.initialize();
        authSession.emit('opens-user');
        await tester.pump();
        unawaited(service.dispose());
      }

      expect(stateStore.stateFor('opens-user').appOpenCount, 14);
      expect(dialogCount, 0);
    });

    testWidgets('15th genuine app launch triggers fallback', (tester) async {
      await pumpHost(tester);

      for (var i = 0; i < 14; i += 1) {
        final service = buildService();
        await service.initialize();
        authSession.emit('fallback-user');
        await tester.pump();
        unawaited(service.dispose());
      }

      final service = buildService();
      dialogActions.add(PlayStoreReviewDialogAction.maybeLater);
      await service.initialize();
      authSession.emit('fallback-user');
      await tester.pump();

      expect(dialogCount, 1);
      expect(
        stateStore.stateFor('fallback-user').appOpenFallbackMilestoneUnlocked,
        isTrue,
      );
      unawaited(service.dispose());
    });

    testWidgets('remote config kill switch blocks automatic prompting', (
      tester,
    ) async {
      configProvider.config = const PlayStoreReviewConfig(
        enabled: false,
        cooldownDays: 30,
        maxRequests: 2,
        fallbackAppOpens: 15,
        promptDelay: Duration.zero,
      );
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('disabled-user');
      await tester.pump();
      bookingStreamSource.emitCustomer('disabled-user', 'booking-1');
      await tester.pump();

      expect(dialogCount, 0);
      expect(stateStore.stateFor('disabled-user').pendingOpportunity, isTrue);
      unawaited(service.dispose());
    });

    testWidgets('remote config fallback threshold is applied dynamically', (
      tester,
    ) async {
      configProvider.config = const PlayStoreReviewConfig(
        enabled: true,
        cooldownDays: 30,
        maxRequests: 2,
        fallbackAppOpens: 2,
        promptDelay: Duration.zero,
      );
      await pumpHost(tester);

      final firstService = buildService();
      await firstService.initialize();
      authSession.emit('dynamic-fallback');
      await tester.pump();
      unawaited(firstService.dispose());

      final secondService = buildService();
      dialogActions.add(PlayStoreReviewDialogAction.maybeLater);
      await secondService.initialize();
      authSession.emit('dynamic-fallback');
      await tester.pump();

      expect(dialogCount, 1);
      expect(stateStore.stateFor('dynamic-fallback').appOpenCount, 2);
      unawaited(secondService.dispose());
    });

    testWidgets('app open increments only once per application session', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('session-user');
      authSession.emit('session-user');
      authSession.emit('session-user');
      await tester.pump();

      expect(stateStore.stateFor('session-user').appOpenCount, 1);
      unawaited(service.dispose());
    });

    testWidgets('native review request increments request count', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('native-user');
      await tester.pump();

      dialogActions.add(PlayStoreReviewDialogAction.rateOnPlayStore);
      bookingStreamSource.emitCustomer('native-user', 'booking-1');
      await tester.pump();

      expect(launcher.requestCount, 1);
      expect(stateStore.stateFor('native-user').requestCount, 1);
      expect(stateStore.stateFor('native-user').pendingOpportunity, isFalse);
      unawaited(service.dispose());
    });

    testWidgets('cooldown blocks another prompt before 30 days', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('cooldown-user');
      await tester.pump();

      dialogActions.add(PlayStoreReviewDialogAction.rateOnPlayStore);
      bookingStreamSource.emitCustomer('cooldown-user', 'booking-1');
      await tester.pump();

      bookingStreamSource.emitCustomer('cooldown-user', 'booking-2');
      await tester.pump();

      expect(dialogCount, 1);
      expect(stateStore.stateFor('cooldown-user').pendingOpportunity, isTrue);
      unawaited(service.dispose());
    });

    testWidgets('pending opportunity can prompt again after cooldown', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('cooldown-pass-user');
      await tester.pump();

      dialogActions.add(PlayStoreReviewDialogAction.rateOnPlayStore);
      bookingStreamSource.emitCustomer('cooldown-pass-user', 'booking-1');
      await tester.pump();
      bookingStreamSource.emitCustomer('cooldown-pass-user', 'booking-2');
      await tester.pump();

      unawaited(service.dispose());

      authSession = _FakeAuthSession();
      final nextSessionService = buildService();
      await nextSessionService.initialize();
      authSession.emit('cooldown-pass-user');
      await tester.pump();
      now = now.add(const Duration(days: 31));
      dialogActions.add(PlayStoreReviewDialogAction.maybeLater);
      await nextSessionService.debugEvaluatePendingOpportunity();
      await tester.pump();

      expect(dialogCount, 2);
      unawaited(nextSessionService.dispose());
    });

    testWidgets('request count at two blocks further automatic prompts', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('limit-user');
      await tester.pump();

      dialogActions.addAll([
        PlayStoreReviewDialogAction.rateOnPlayStore,
        PlayStoreReviewDialogAction.rateOnPlayStore,
      ]);
      bookingStreamSource.emitCustomer('limit-user', 'booking-1');
      await tester.pump();
      bookingStreamSource.emitCustomer('limit-user', 'booking-2');
      await tester.pump();

      unawaited(service.dispose());

      authSession = _FakeAuthSession();
      final secondSessionService = buildService();
      await secondSessionService.initialize();
      authSession.emit('limit-user');
      await tester.pump();
      now = now.add(const Duration(days: 31));
      await secondSessionService.debugEvaluatePendingOpportunity();
      await tester.pump();

      expect(stateStore.stateFor('limit-user').requestCount, 2);

      expect(stateStore.stateFor('limit-user').requestCount, 2);
      expect(launcher.requestCount, 2);
      unawaited(secondSessionService.dispose());
    });

    testWidgets(
      'Maybe Later, No Thanks, and Close never increment request count',
      (tester) async {
        final service = buildService();
        await pumpHost(tester);
        await service.initialize();

        authSession.emit('dismiss-user');
        await tester.pump();

        dialogActions.addAll([
          PlayStoreReviewDialogAction.maybeLater,
          PlayStoreReviewDialogAction.noThanks,
          PlayStoreReviewDialogAction.close,
        ]);
        bookingStreamSource.emitCustomer('dismiss-user', 'booking-1');
        await tester.pump();
        unawaited(service.dispose());

        authSession = _FakeAuthSession();
        final secondService = buildService();
        await secondService.initialize();
        authSession.emit('dismiss-user');
        await tester.pump();
        now = now.add(const Duration(days: 31));
        await secondService.debugEvaluatePendingOpportunity();
        await tester.pump();
        unawaited(secondService.dispose());

        authSession = _FakeAuthSession();
        final thirdService = buildService();
        await thirdService.initialize();
        authSession.emit('dismiss-user');
        await tester.pump();
        now = now.add(const Duration(days: 31));
        await thirdService.debugEvaluatePendingOpportunity();
        await tester.pump();

        expect(stateStore.stateFor('dismiss-user').requestCount, 0);
        expect(dialogCount, 3);
        unawaited(thirdService.dispose());
      },
    );

    testWidgets('same booking completion is idempotent', (tester) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('idempotent-user');
      await tester.pump();

      dialogActions.add(PlayStoreReviewDialogAction.maybeLater);
      bookingStreamSource.emitCustomer('idempotent-user', 'booking-repeat');
      bookingStreamSource.emitCustomer('idempotent-user', 'booking-repeat');
      await tester.pump();

      expect(dialogCount, 1);
      expect(
        stateStore.stateFor('idempotent-user').completedBookingMilestoneCount,
        1,
      );
      unawaited(service.dispose());
    });

    testWidgets('simultaneous triggers do not produce two dialogs', (
      tester,
    ) async {
      final service = buildService();
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('simultaneous-user');
      socialPostCounter.counts['simultaneous-user'] = 2;
      await tester.pump();

      dialogActions.add(PlayStoreReviewDialogAction.maybeLater);
      await Future.wait([
        service.debugHandleCompletedBookingForCurrentUser('booking-1'),
        service.debugHandleSuccessfulPostForCurrentUser(),
      ]);
      await tester.pump();

      expect(dialogCount, 1);
      unawaited(service.dispose());
    });

    testWidgets('backgrounded app does not show prompt until resumed', (
      tester,
    ) async {
      final completer = Completer<void>();
      final service = buildService(delayScheduler: (_) => completer.future);
      await pumpHost(tester);
      await service.initialize();

      authSession.emit('background-user');
      await tester.pump();

      dialogActions.add(PlayStoreReviewDialogAction.maybeLater);
      unawaited(service.debugHandleCompletedBookingForCurrentUser('booking-1'));
      await tester.pump();
      service.didChangeAppLifecycleState(AppLifecycleState.paused);
      completer.complete();
      await tester.pump();

      expect(dialogCount, 0);

      service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();

      expect(dialogCount, 1);
      unawaited(service.dispose());
    });
  });
}

class _FakeAuthSession implements PlayStoreReviewAuthSession {
  final StreamController<String?> _controller =
      StreamController<String?>.broadcast();
  String? _currentUid;

  @override
  String? get currentUid => _currentUid;

  void emit(String? uid) {
    _currentUid = uid;
    _controller.add(uid);
  }

  @override
  Stream<String?> authStateChanges() => _controller.stream;
}

class _MemoryPlayStoreReviewStateStore implements PlayStoreReviewStateStore {
  _MemoryPlayStoreReviewStateStore(this._now);

  final DateTime Function() _now;
  final Map<String, PlayStoreReviewState> _states =
      <String, PlayStoreReviewState>{};
  final Map<String, Set<String>> _processedBookings = <String, Set<String>>{};

  PlayStoreReviewState stateFor(String uid) =>
      _states[uid] ?? const PlayStoreReviewState();

  @override
  Future<PlayStoreReviewState> loadState(String uid) async => stateFor(uid);

  @override
  Future<void> saveState(
    String uid,
    PlayStoreReviewState state, {
    required bool includeCreatedAt,
    bool includeServerLastRequestedAt = false,
  }) async {
    _states[uid] = includeServerLastRequestedAt
        ? state.copyWith(lastRequestedAt: _now())
        : state;
  }

  @override
  Future<bool> markCompletedBookingProcessed(
    String uid,
    String bookingId,
  ) async {
    final processed = _processedBookings.putIfAbsent(uid, () => <String>{});
    if (processed.contains(bookingId)) {
      return false;
    }
    processed.add(bookingId);
    return true;
  }
}

class _FakePlayReviewLauncher implements PlayReviewLauncher {
  bool available = true;
  int requestCount = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> requestReview() async {
    requestCount += 1;
  }
}

class _FakeCompletedBookingStreamSource
    implements PlayStoreCompletedBookingMilestoneStreamSource {
  final Map<String, StreamController<String>> _customerControllers =
      <String, StreamController<String>>{};
  final Map<String, StreamController<String>> _providerControllers =
      <String, StreamController<String>>{};

  void emitCustomer(String uid, String bookingId) {
    _customerControllers
        .putIfAbsent(uid, () => StreamController<String>.broadcast())
        .add(bookingId);
  }

  void emitProvider(String uid, String bookingId) {
    _providerControllers
        .putIfAbsent(uid, () => StreamController<String>.broadcast())
        .add(bookingId);
  }

  @override
  Stream<String> watchCompletedBookingIdsForCustomer(String uid) {
    return _customerControllers
        .putIfAbsent(uid, () => StreamController<String>.broadcast())
        .stream;
  }

  @override
  Stream<String> watchCompletedBookingIdsForProvider(String uid) {
    return _providerControllers
        .putIfAbsent(uid, () => StreamController<String>.broadcast())
        .stream;
  }
}

class _FakeSocialPostCounter implements PlayStoreReviewSocialPostCounter {
  final Map<String, int> counts = <String, int>{};

  @override
  Future<int> fetchPersistedPostCountUpTo(
    String uid, {
    required int limit,
  }) async {
    final count = counts[uid] ?? 0;
    return count > limit ? limit : count;
  }
}

class _FakePlayStoreReviewConfigProvider
    implements PlayStoreReviewConfigProvider {
  PlayStoreReviewConfig config = const PlayStoreReviewConfig(
    enabled: true,
    cooldownDays: 30,
    maxRequests: 2,
    fallbackAppOpens: 15,
    promptDelay: Duration.zero,
  );

  @override
  PlayStoreReviewConfig currentConfig() => config;

  @override
  Future<void> initialize() async {}
}
