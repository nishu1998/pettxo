import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';

import '../../features/social/data/services/post_publish_coordinator.dart';
import '../widgets/play_store_review_dialog.dart';
import 'app_loader.dart';
import 'remote_config_service.dart';

enum PlayStoreReviewOpportunitySource {
  completedBooking,
  secondSocialPost,
  appOpenFallback,
}

enum PlayStoreReviewDialogAction {
  rateOnPlayStore,
  maybeLater,
  noThanks,
  close,
}

@immutable
class PlayStoreReviewState {
  const PlayStoreReviewState({
    this.appOpenCount = 0,
    this.successfulPostCount = 0,
    this.completedBookingMilestoneCount = 0,
    this.completedBookingMilestoneUnlocked = false,
    this.secondSocialPostMilestoneUnlocked = false,
    this.appOpenFallbackMilestoneUnlocked = false,
    this.pendingOpportunity = false,
    this.pendingOpportunitySource,
    this.requestCount = 0,
    this.lastRequestedAt,
  });

  final int appOpenCount;
  final int successfulPostCount;
  final int completedBookingMilestoneCount;
  final bool completedBookingMilestoneUnlocked;
  final bool secondSocialPostMilestoneUnlocked;
  final bool appOpenFallbackMilestoneUnlocked;
  final bool pendingOpportunity;
  final PlayStoreReviewOpportunitySource? pendingOpportunitySource;
  final int requestCount;
  final DateTime? lastRequestedAt;

  PlayStoreReviewState copyWith({
    int? appOpenCount,
    int? successfulPostCount,
    int? completedBookingMilestoneCount,
    bool? completedBookingMilestoneUnlocked,
    bool? secondSocialPostMilestoneUnlocked,
    bool? appOpenFallbackMilestoneUnlocked,
    bool? pendingOpportunity,
    Object? pendingOpportunitySource = _playStoreReviewSentinel,
    int? requestCount,
    Object? lastRequestedAt = _playStoreReviewSentinel,
  }) {
    return PlayStoreReviewState(
      appOpenCount: appOpenCount ?? this.appOpenCount,
      successfulPostCount: successfulPostCount ?? this.successfulPostCount,
      completedBookingMilestoneCount:
          completedBookingMilestoneCount ?? this.completedBookingMilestoneCount,
      completedBookingMilestoneUnlocked:
          completedBookingMilestoneUnlocked ??
          this.completedBookingMilestoneUnlocked,
      secondSocialPostMilestoneUnlocked:
          secondSocialPostMilestoneUnlocked ??
          this.secondSocialPostMilestoneUnlocked,
      appOpenFallbackMilestoneUnlocked:
          appOpenFallbackMilestoneUnlocked ??
          this.appOpenFallbackMilestoneUnlocked,
      pendingOpportunity: pendingOpportunity ?? this.pendingOpportunity,
      pendingOpportunitySource:
          identical(pendingOpportunitySource, _playStoreReviewSentinel)
          ? this.pendingOpportunitySource
          : pendingOpportunitySource as PlayStoreReviewOpportunitySource?,
      requestCount: requestCount ?? this.requestCount,
      lastRequestedAt: identical(lastRequestedAt, _playStoreReviewSentinel)
          ? this.lastRequestedAt
          : lastRequestedAt as DateTime?,
    );
  }
}

const Object _playStoreReviewSentinel = Object();

abstract class PlayReviewLauncher {
  Future<bool> isAvailable();

  Future<void> requestReview();
}

class InAppPlayReviewLauncher implements PlayReviewLauncher {
  InAppPlayReviewLauncher({InAppReview? inAppReview})
    : _inAppReview = inAppReview ?? InAppReview.instance;

  final InAppReview _inAppReview;

  @override
  Future<bool> isAvailable() => _inAppReview.isAvailable();

  @override
  Future<void> requestReview() => _inAppReview.requestReview();
}

abstract class PlayStoreReviewAuthSession {
  String? get currentUid;

  Stream<String?> authStateChanges();
}

class FirebasePlayStoreReviewAuthSession implements PlayStoreReviewAuthSession {
  FirebasePlayStoreReviewAuthSession({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  String? get currentUid => _auth.currentUser?.uid;

  @override
  Stream<String?> authStateChanges() {
    return _auth.authStateChanges().map((user) => user?.uid);
  }
}

abstract class PlayStoreCompletedBookingMilestoneStreamSource {
  Stream<String> watchCompletedBookingIdsForCustomer(String uid);

  Stream<String> watchCompletedBookingIdsForProvider(String uid);
}

class FirestorePlayStoreCompletedBookingMilestoneStreamSource
    implements PlayStoreCompletedBookingMilestoneStreamSource {
  FirestorePlayStoreCompletedBookingMilestoneStreamSource({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Stream<String> watchCompletedBookingIdsForCustomer(String uid) {
    return _firestore
        .collection('bookings')
        .where('customerId', isEqualTo: uid)
        .where('stateQueryValue', isEqualTo: 'COMPLETED_FINAL')
        .snapshots()
        .expand((snapshot) => snapshot.docs.map((doc) => doc.id));
  }

  @override
  Stream<String> watchCompletedBookingIdsForProvider(String uid) {
    return _firestore
        .collection('bookings')
        .where('serviceOwnerId', isEqualTo: uid)
        .where('stateQueryValue', isEqualTo: 'COMPLETED_FINAL')
        .snapshots()
        .expand((snapshot) => snapshot.docs.map((doc) => doc.id));
  }
}

abstract class PlayStoreReviewSocialPostCounter {
  Future<int> fetchPersistedPostCountUpTo(String uid, {required int limit});
}

class FirestorePlayStoreReviewSocialPostCounter
    implements PlayStoreReviewSocialPostCounter {
  FirestorePlayStoreReviewSocialPostCounter({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<int> fetchPersistedPostCountUpTo(
    String uid, {
    required int limit,
  }) async {
    final snapshot = await _firestore
        .collection('socialPosts')
        .where('authorId', isEqualTo: uid)
        .limit(limit)
        .get();
    return snapshot.docs.length;
  }
}

abstract class PlayStoreReviewStateStore {
  Future<PlayStoreReviewState> loadState(String uid);

  Future<bool> stateDocumentExists(String uid);

  Future<void> saveState(
    String uid,
    PlayStoreReviewState state, {
    required bool includeCreatedAt,
    bool includeServerLastRequestedAt = false,
  });

  Future<bool> markCompletedBookingProcessed(String uid, String bookingId);
}

class FirestorePlayStoreReviewStateStore implements PlayStoreReviewStateStore {
  FirestorePlayStoreReviewStateStore({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _stateRef(String uid) {
    return _firestore
        .collection('userPrivate')
        .doc(uid)
        .collection('playStoreReview')
        .doc('state');
  }

  DocumentReference<Map<String, dynamic>> _processedBookingRef(
    String uid,
    String bookingId,
  ) {
    return _firestore
        .collection('userPrivate')
        .doc(uid)
        .collection('playStoreReviewCompletedBookings')
        .doc(bookingId);
  }

  @override
  Future<PlayStoreReviewState> loadState(String uid) async {
    final snapshot = await _stateRef(uid).get();
    return _readState(snapshot.data());
  }

  @override
  Future<bool> stateDocumentExists(String uid) async {
    final snapshot = await _stateRef(uid).get();
    return snapshot.exists;
  }

  @override
  Future<void> saveState(
    String uid,
    PlayStoreReviewState state, {
    required bool includeCreatedAt,
    bool includeServerLastRequestedAt = false,
  }) async {
    await _stateRef(uid).set(
      _stateMap(
        uid: uid,
        state: state,
        includeCreatedAt: includeCreatedAt,
        includeServerLastRequestedAt: includeServerLastRequestedAt,
      ),
      SetOptions(merge: true),
    );
  }

  @override
  Future<bool> markCompletedBookingProcessed(
    String uid,
    String bookingId,
  ) async {
    return _firestore.runTransaction((transaction) async {
      final processedRef = _processedBookingRef(uid, bookingId);
      final processedSnapshot = await transaction.get(processedRef);
      if (processedSnapshot.exists) {
        return false;
      }
      transaction.set(processedRef, {
        'bookingId': bookingId,
        'processedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
  }

  PlayStoreReviewState _readState(Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return PlayStoreReviewState(
      appOpenCount: (map['appOpenCount'] as num?)?.toInt() ?? 0,
      successfulPostCount: (map['successfulPostCount'] as num?)?.toInt() ?? 0,
      completedBookingMilestoneCount:
          (map['completedBookingMilestoneCount'] as num?)?.toInt() ?? 0,
      completedBookingMilestoneUnlocked:
          map['completedBookingMilestoneUnlocked'] == true,
      secondSocialPostMilestoneUnlocked:
          map['secondSocialPostMilestoneUnlocked'] == true,
      appOpenFallbackMilestoneUnlocked:
          map['appOpenFallbackMilestoneUnlocked'] == true,
      pendingOpportunity: map['pendingOpportunity'] == true,
      pendingOpportunitySource: _parseOpportunitySource(
        map['pendingOpportunitySource'] as String?,
      ),
      requestCount: (map['requestCount'] as num?)?.toInt() ?? 0,
      lastRequestedAt: _readDate(map['lastRequestedAt']),
    );
  }

  Map<String, dynamic> _stateMap({
    required String uid,
    required PlayStoreReviewState state,
    required bool includeCreatedAt,
    required bool includeServerLastRequestedAt,
  }) {
    return <String, dynamic>{
      'uid': uid,
      if (includeCreatedAt) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'appOpenCount': state.appOpenCount,
      'successfulPostCount': state.successfulPostCount,
      'completedBookingMilestoneCount': state.completedBookingMilestoneCount,
      'completedBookingMilestoneUnlocked':
          state.completedBookingMilestoneUnlocked,
      'secondSocialPostMilestoneUnlocked':
          state.secondSocialPostMilestoneUnlocked,
      'appOpenFallbackMilestoneUnlocked':
          state.appOpenFallbackMilestoneUnlocked,
      'pendingOpportunity': state.pendingOpportunity,
      'pendingOpportunitySource': state.pendingOpportunitySource?.name,
      'requestCount': state.requestCount,
      if (includeServerLastRequestedAt)
        'lastRequestedAt': FieldValue.serverTimestamp(),
    };
  }

  PlayStoreReviewOpportunitySource? _parseOpportunitySource(String? raw) {
    return switch ((raw ?? '').trim()) {
      'completedBooking' => PlayStoreReviewOpportunitySource.completedBooking,
      'secondSocialPost' => PlayStoreReviewOpportunitySource.secondSocialPost,
      'appOpenFallback' => PlayStoreReviewOpportunitySource.appOpenFallback,
      _ => null,
    };
  }

  DateTime? _readDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

typedef PlayStoreReviewDialogPresenter =
    Future<PlayStoreReviewDialogAction?> Function(BuildContext context);

typedef PlayStoreReviewDelayScheduler =
    Future<void> Function(Duration duration);

abstract class PlayStoreReviewConfigProvider {
  PlayStoreReviewConfig currentConfig();

  Future<void> initialize();
}

class RemoteConfigPlayStoreReviewConfigProvider
    implements PlayStoreReviewConfigProvider {
  RemoteConfigPlayStoreReviewConfigProvider({
    RemoteConfigService? remoteConfigService,
  }) : _remoteConfigService = remoteConfigService ?? RemoteConfigService();

  final RemoteConfigService _remoteConfigService;

  @override
  PlayStoreReviewConfig currentConfig() =>
      _remoteConfigService.playStoreReviewConfig;

  @override
  Future<void> initialize() => _remoteConfigService.init();
}

class PlayStoreReviewService with WidgetsBindingObserver {
  PlayStoreReviewService({
    PlayStoreReviewAuthSession? authSession,
    PlayStoreReviewStateStore? stateStore,
    PlayReviewLauncher? reviewLauncher,
    PlayStoreCompletedBookingMilestoneStreamSource?
    completedBookingStreamSource,
    PlayStoreReviewSocialPostCounter? socialPostCounter,
    PlayStoreReviewConfigProvider? configProvider,
    ValueListenable<PostPublishState>? postPublishStateListenable,
    PlayStoreReviewDialogPresenter? dialogPresenter,
    PlayStoreReviewDelayScheduler? delayScheduler,
    DateTime Function()? now,
  }) : _authSession = authSession ?? FirebasePlayStoreReviewAuthSession(),
       _stateStore = stateStore ?? FirestorePlayStoreReviewStateStore(),
       _reviewLauncher = reviewLauncher ?? InAppPlayReviewLauncher(),
       _completedBookingStreamSource =
           completedBookingStreamSource ??
           FirestorePlayStoreCompletedBookingMilestoneStreamSource(),
       _socialPostCounter =
           socialPostCounter ?? FirestorePlayStoreReviewSocialPostCounter(),
       _configProvider =
           configProvider ?? RemoteConfigPlayStoreReviewConfigProvider(),
       _postPublishStateListenable =
           postPublishStateListenable ??
           PostPublishCoordinator.instance.stateListenable,
       _dialogPresenter =
           dialogPresenter ??
           ((context) => PlayStoreReviewDialog.show(context: context)),
       _delayScheduler = delayScheduler ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  PlayStoreReviewService._singleton() : this();

  static final PlayStoreReviewService instance =
      PlayStoreReviewService._singleton();

  final PlayStoreReviewAuthSession _authSession;
  final PlayStoreReviewStateStore _stateStore;
  final PlayReviewLauncher _reviewLauncher;
  final PlayStoreCompletedBookingMilestoneStreamSource
  _completedBookingStreamSource;
  final PlayStoreReviewSocialPostCounter _socialPostCounter;
  final PlayStoreReviewConfigProvider _configProvider;
  final ValueListenable<PostPublishState> _postPublishStateListenable;
  final PlayStoreReviewDialogPresenter _dialogPresenter;
  final PlayStoreReviewDelayScheduler _delayScheduler;
  final DateTime Function() _now;

  StreamSubscription<String?>? _authSubscription;
  StreamSubscription<String>? _customerCompletedBookingsSubscription;
  StreamSubscription<String>? _providerCompletedBookingsSubscription;
  bool _initialized = false;
  bool _dialogVisible = false;
  bool _nativeRequestInFlight = false;
  bool _sessionSuppressed = false;
  bool _promptScheduled = false;
  String? _currentUid;
  PlayStoreReviewState? _cachedState;
  String? _cachedStateUid;
  bool? _cachedStateExists;
  Future<PlayStoreReviewState>? _stateLoadFuture;
  Future<void> _stateMutationQueue = Future<void>.value();
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  int _lastHandledPublishEventId = 0;
  final Set<String> _countedAppOpenUidsThisProcess = <String>{};

  @visibleForTesting
  bool get isPromptScheduled => _promptScheduled;

  @visibleForTesting
  bool get isSessionSuppressed => _sessionSuppressed;

  Future<void> initialize() async {
    if (_initialized || _authSubscription != null) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = _authSession.authStateChanges().listen(
      _handleAuthChanged,
    );
    _postPublishStateListenable.addListener(_handlePostPublishStateChanged);
    unawaited(
      _configProvider.initialize().then((_) {
        if (kDebugMode) {
          final config = _configProvider.currentConfig();
          debugPrint(
            'PlayStoreReviewService remote config ready -> enabled=${config.enabled} cooldownDays=${config.cooldownDays} maxRequests=${config.maxRequests} fallbackAppOpens=${config.fallbackAppOpens} promptDelaySeconds=${config.promptDelay.inSeconds}',
          );
        }
      }),
    );
    final currentUid = _authSession.currentUid?.trim() ?? '';
    if (currentUid.isNotEmpty) {
      unawaited(_handleAuthChanged(currentUid));
    }
  }

  Future<void> dispose() async {
    if (!_initialized && _authSubscription == null) return;
    WidgetsBinding.instance.removeObserver(this);
    await _authSubscription?.cancel();
    await _customerCompletedBookingsSubscription?.cancel();
    await _providerCompletedBookingsSubscription?.cancel();
    _authSubscription = null;
    _customerCompletedBookingsSubscription = null;
    _providerCompletedBookingsSubscription = null;
    _postPublishStateListenable.removeListener(_handlePostPublishStateChanged);
    _initialized = false;
    _currentUid = null;
    _clearCachedState();
    _promptScheduled = false;
    _dialogVisible = false;
    _nativeRequestInFlight = false;
    _sessionSuppressed = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_evaluatePendingOpportunity(reason: 'app-resumed'));
    }
  }

  @visibleForTesting
  Future<void> debugTriggerPromptForCurrentUser() async {
    final uid = (_currentUid ?? '').trim();
    if (uid.isEmpty || !kDebugMode) return;
    final seeded = await _enqueueStateMutation(() async {
      final current = await _loadCachedState(uid);
      final bookingId = 'debug-booking-${_now().millisecondsSinceEpoch}';
      final recorded = await _stateStore.markCompletedBookingProcessed(
        uid,
        bookingId,
      );
      if (!recorded) return current;
      final next = current.copyWith(
        completedBookingMilestoneCount:
            current.completedBookingMilestoneCount + 1,
        completedBookingMilestoneUnlocked: true,
        pendingOpportunity: true,
        pendingOpportunitySource:
            PlayStoreReviewOpportunitySource.completedBooking,
      );
      await _persistState(uid, next);
      return next;
    }, reason: 'debug-trigger');
    await _schedulePromptIfAllowed(uid, seeded, reason: 'debug-trigger');
  }

  @visibleForTesting
  Future<void> debugHandleCompletedBookingForCurrentUser(
    String bookingId,
  ) async {
    final uid = (_currentUid ?? '').trim();
    if (uid.isEmpty) return;
    await _handleCompletedBookingMilestone(
      uid,
      bookingId,
      reason: 'debug-completed-booking',
    );
  }

  @visibleForTesting
  Future<void> debugHandleSuccessfulPostForCurrentUser() async {
    final uid = (_currentUid ?? '').trim();
    if (uid.isEmpty) return;
    await _handleSuccessfulPostPublished(uid);
  }

  @visibleForTesting
  Future<void> debugEvaluatePendingOpportunity() async {
    await _evaluatePendingOpportunity(reason: 'debug-evaluate');
  }

  @visibleForTesting
  Future<PlayStoreReviewState?> debugCachedState() async {
    final uid = (_currentUid ?? '').trim();
    if (uid.isEmpty) return null;
    return _loadCachedState(uid);
  }

  @visibleForTesting
  PlayStoreReviewConfig debugCurrentConfig() => _configProvider.currentConfig();

  Future<void> _handleAuthChanged(String? uid) async {
    final nextUid = uid?.trim() ?? '';
    if (nextUid == _currentUid) {
      await _recordAppOpenIfNeeded(nextUid);
      await _evaluatePendingOpportunity(reason: 'auth-refresh');
      return;
    }

    await _customerCompletedBookingsSubscription?.cancel();
    await _providerCompletedBookingsSubscription?.cancel();
    _customerCompletedBookingsSubscription = null;
    _providerCompletedBookingsSubscription = null;
    _clearCachedState();
    _promptScheduled = false;
    _dialogVisible = false;
    _nativeRequestInFlight = false;
    _sessionSuppressed = false;
    _currentUid = nextUid.isEmpty ? null : nextUid;

    if (nextUid.isEmpty) return;

    await _loadCachedState(nextUid);
    await _primeSuccessfulPostCount(nextUid);
    await _recordAppOpenIfNeeded(nextUid);
    _attachCompletedBookingListeners(nextUid);
    await _evaluatePendingOpportunity(reason: 'auth-changed');
  }

  Future<void> _recordAppOpenIfNeeded(String uid) async {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) return;
    if (_countedAppOpenUidsThisProcess.contains(normalizedUid)) return;
    _countedAppOpenUidsThisProcess.add(normalizedUid);
    final nextState = await _mutateState(
      normalizedUid,
      reason: 'record-app-open',
      transform: (current) {
        final config = _configProvider.currentConfig();
        final nextOpenCount = current.appOpenCount + 1;
        final shouldUnlockFallback =
            nextOpenCount >= config.fallbackAppOpens &&
            !current.completedBookingMilestoneUnlocked &&
            !current.secondSocialPostMilestoneUnlocked &&
            !current.appOpenFallbackMilestoneUnlocked;
        return current.copyWith(
          appOpenCount: nextOpenCount,
          appOpenFallbackMilestoneUnlocked:
              current.appOpenFallbackMilestoneUnlocked || shouldUnlockFallback,
          pendingOpportunity:
              current.pendingOpportunity || shouldUnlockFallback,
          pendingOpportunitySource: shouldUnlockFallback
              ? PlayStoreReviewOpportunitySource.appOpenFallback
              : current.pendingOpportunitySource,
        );
      },
    );
    await _schedulePromptIfAllowed(
      normalizedUid,
      nextState,
      reason: 'app-open',
    );
  }

  Future<void> _primeSuccessfulPostCount(String uid) async {
    try {
      final currentState = await _loadCachedState(uid);
      if (currentState.secondSocialPostMilestoneUnlocked ||
          currentState.successfulPostCount >= 2) {
        return;
      }
      final persistedPostCount = await _socialPostCounter
          .fetchPersistedPostCountUpTo(uid, limit: 2);
      await _mutateState(
        uid,
        reason: 'prime-successful-post-count',
        transform: (current) {
          if (persistedPostCount <= current.successfulPostCount) {
            return current;
          }
          final shouldUnlockSecondPost =
              !current.secondSocialPostMilestoneUnlocked &&
              current.successfulPostCount < 2 &&
              persistedPostCount >= 2;
          return current.copyWith(
            successfulPostCount: persistedPostCount,
            secondSocialPostMilestoneUnlocked:
                current.secondSocialPostMilestoneUnlocked ||
                shouldUnlockSecondPost,
            pendingOpportunity:
                current.pendingOpportunity || shouldUnlockSecondPost,
            pendingOpportunitySource: shouldUnlockSecondPost
                ? PlayStoreReviewOpportunitySource.secondSocialPost
                : current.pendingOpportunitySource,
          );
        },
      );
    } catch (error) {
      debugPrint('PlayStoreReviewService post baseline skipped: $error');
    }
  }

  void _attachCompletedBookingListeners(String uid) {
    _customerCompletedBookingsSubscription = _completedBookingStreamSource
        .watchCompletedBookingIdsForCustomer(uid)
        .listen(
          (bookingId) => _handleCompletedBookingMilestone(
            uid,
            bookingId,
            reason: 'customer-completed-bookings',
          ),
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              'PlayStoreReviewService customer booking listener failed: $error',
            );
            debugPrintStack(stackTrace: stackTrace);
          },
        );
    _providerCompletedBookingsSubscription = _completedBookingStreamSource
        .watchCompletedBookingIdsForProvider(uid)
        .listen(
          (bookingId) => _handleCompletedBookingMilestone(
            uid,
            bookingId,
            reason: 'provider-completed-bookings',
          ),
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              'PlayStoreReviewService provider booking listener failed: $error',
            );
            debugPrintStack(stackTrace: stackTrace);
          },
        );
  }

  Future<void> _handleCompletedBookingMilestone(
    String uid,
    String bookingId, {
    required String reason,
  }) async {
    final nextState = await _enqueueStateMutation(() async {
      final current = await _loadCachedState(uid);
      final recorded = await _stateStore.markCompletedBookingProcessed(
        uid,
        bookingId,
      );
      if (!recorded) return current;
      final next = current.copyWith(
        completedBookingMilestoneCount:
            current.completedBookingMilestoneCount + 1,
        completedBookingMilestoneUnlocked: true,
        pendingOpportunity: true,
        pendingOpportunitySource:
            PlayStoreReviewOpportunitySource.completedBooking,
      );
      await _persistState(uid, next);
      return next;
    }, reason: 'completed-booking:$bookingId');
    if ((_currentUid ?? '') != uid) return;
    await _schedulePromptIfAllowed(uid, nextState, reason: reason);
  }

  void _handlePostPublishStateChanged() {
    final publishState = _postPublishStateListenable.value;
    if (publishState.phase != PostPublishPhase.success) return;
    if (publishState.eventId == _lastHandledPublishEventId) return;
    _lastHandledPublishEventId = publishState.eventId;
    final uid = (_currentUid ?? '').trim();
    final postAuthorId = publishState.post?.authorId.trim() ?? '';
    if (uid.isEmpty || postAuthorId != uid) return;
    unawaited(_handleSuccessfulPostPublished(uid));
  }

  Future<void> _handleSuccessfulPostPublished(String uid) async {
    try {
      final nextState = await _mutateState(
        uid,
        reason: 'successful-social-post',
        transform: (current) {
          final nextCount = current.successfulPostCount + 1;
          final shouldUnlockSecondPost =
              !current.secondSocialPostMilestoneUnlocked &&
              current.successfulPostCount < 2 &&
              nextCount >= 2;
          return current.copyWith(
            successfulPostCount: nextCount,
            secondSocialPostMilestoneUnlocked:
                current.secondSocialPostMilestoneUnlocked ||
                shouldUnlockSecondPost,
            pendingOpportunity:
                current.pendingOpportunity || shouldUnlockSecondPost,
            pendingOpportunitySource: shouldUnlockSecondPost
                ? PlayStoreReviewOpportunitySource.secondSocialPost
                : current.pendingOpportunitySource,
          );
        },
      );
      await _schedulePromptIfAllowed(
        uid,
        nextState,
        reason: 'successful-social-post',
      );
    } catch (error, stackTrace) {
      debugPrint('PlayStoreReviewService post milestone skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _evaluatePendingOpportunity({required String reason}) async {
    final uid = (_currentUid ?? '').trim();
    if (uid.isEmpty) return;
    try {
      final state = await _loadCachedState(uid);
      await _schedulePromptIfAllowed(uid, state, reason: reason);
    } catch (error, stackTrace) {
      debugPrint('PlayStoreReviewService evaluation skipped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _schedulePromptIfAllowed(
    String uid,
    PlayStoreReviewState state, {
    required String reason,
  }) async {
    final config = _configProvider.currentConfig();
    if (!_canShowPromptForState(state, config: config)) return;
    if (_promptScheduled || _dialogVisible || _nativeRequestInFlight) return;
    if (!_isForegroundReady) return;

    _promptScheduled = true;
    await _delayScheduler(config.promptDelay);
    _promptScheduled = false;

    if ((_currentUid ?? '') != uid) return;
    if (!_isForegroundReady || _dialogVisible || _nativeRequestInFlight) {
      return;
    }

    final refreshedState = await _loadCachedState(uid);
    final refreshedConfig = _configProvider.currentConfig();
    if (!_canShowPromptForState(refreshedState, config: refreshedConfig)) {
      return;
    }

    final context = AppLoader.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    _dialogVisible = true;
    try {
      final action = await _dialogPresenter(context);
      await _handleDialogAction(uid, action, refreshedState, reason: reason);
    } finally {
      _dialogVisible = false;
    }
  }

  bool _canShowPromptForState(
    PlayStoreReviewState state, {
    required PlayStoreReviewConfig config,
  }) {
    if (!config.enabled) return false;
    if (_sessionSuppressed) return false;
    if (!state.pendingOpportunity) return false;
    if (state.requestCount >= config.maxRequests) return false;
    final lastRequestedAt = state.lastRequestedAt;
    if (lastRequestedAt == null) return true;
    return _now().difference(lastRequestedAt) >=
        Duration(days: config.cooldownDays);
  }

  bool get _isForegroundReady =>
      _lifecycleState == AppLifecycleState.resumed &&
      AppLoader.navigatorKey.currentContext != null;

  Future<void> _handleDialogAction(
    String uid,
    PlayStoreReviewDialogAction? action,
    PlayStoreReviewState currentState, {
    required String reason,
  }) async {
    switch (action) {
      case PlayStoreReviewDialogAction.rateOnPlayStore:
        await _attemptNativeReviewRequest(uid, currentState);
        break;
      case PlayStoreReviewDialogAction.maybeLater:
      case PlayStoreReviewDialogAction.noThanks:
      case PlayStoreReviewDialogAction.close:
      case null:
        _sessionSuppressed = true;
        break;
    }

    if ((_currentUid ?? '') == uid) {
      await _evaluatePendingOpportunity(reason: '$reason-post-dialog');
    }
  }

  Future<void> _attemptNativeReviewRequest(
    String uid,
    PlayStoreReviewState currentState,
  ) async {
    if (_nativeRequestInFlight) return;
    final config = _configProvider.currentConfig();
    if (!_canShowPromptForState(currentState, config: config)) return;

    _nativeRequestInFlight = true;
    try {
      final isAvailable = await _reviewLauncher.isAvailable();
      if (!isAvailable) return;

      var attempted = false;
      try {
        attempted = true;
        await _reviewLauncher.requestReview();
      } finally {
        if (attempted) {
          await _mutateState(
            uid,
            reason: 'mark-native-review-requested',
            includeServerLastRequestedAt: true,
            transform: (current) => current.copyWith(
              requestCount: current.requestCount + 1,
              pendingOpportunity: false,
              pendingOpportunitySource: null,
              lastRequestedAt: _now(),
            ),
          );
        }
      }
    } catch (error, stackTrace) {
      debugPrint('PlayStoreReviewService requestReview failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _nativeRequestInFlight = false;
    }
  }

  Future<PlayStoreReviewState> _loadCachedState(String uid) async {
    if (_cachedStateUid == uid && _cachedState != null) {
      return _cachedState!;
    }
    final pending = _stateLoadFuture;
    if (_cachedStateUid == uid && pending != null) {
      return pending;
    }
    final future = _stateStore.loadState(uid).then((state) async {
      _cachedStateUid = uid;
      _cachedState = state;
      _cachedStateExists = await _stateStore.stateDocumentExists(uid);
      _stateLoadFuture = null;
      return state;
    });
    _cachedStateUid = uid;
    _stateLoadFuture = future;
    return future;
  }

  Future<PlayStoreReviewState> _mutateState(
    String uid, {
    required String reason,
    required PlayStoreReviewState Function(PlayStoreReviewState current)
    transform,
    bool includeServerLastRequestedAt = false,
  }) {
    return _enqueueStateMutation(() async {
      final current = await _loadCachedState(uid);
      final next = transform(current);
      if (_statesEqual(current, next)) return current;
      await _persistState(
        uid,
        next,
        includeServerLastRequestedAt: includeServerLastRequestedAt,
      );
      return next;
    }, reason: reason);
  }

  Future<PlayStoreReviewState> _enqueueStateMutation(
    Future<PlayStoreReviewState> Function() task, {
    required String reason,
  }) {
    final completer = Completer<PlayStoreReviewState>();
    _stateMutationQueue = _stateMutationQueue.then((_) async {
      try {
        final result = await task();
        if (kDebugMode) {
          debugPrint('PlayStoreReviewService state mutation -> $reason');
        }
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _persistState(
    String uid,
    PlayStoreReviewState state, {
    bool includeServerLastRequestedAt = false,
  }) async {
    final includeCreatedAt =
        _cachedStateUid != uid ||
        _cachedState == null ||
        _cachedStateExists != true;
    await _stateStore.saveState(
      uid,
      state,
      includeCreatedAt: includeCreatedAt,
      includeServerLastRequestedAt: includeServerLastRequestedAt,
    );
    _cachedStateUid = uid;
    _cachedState = state;
    _cachedStateExists = true;
  }

  void _clearCachedState() {
    _cachedState = null;
    _cachedStateUid = null;
    _cachedStateExists = null;
    _stateLoadFuture = null;
  }

  bool _statesEqual(PlayStoreReviewState left, PlayStoreReviewState right) {
    return left.appOpenCount == right.appOpenCount &&
        left.successfulPostCount == right.successfulPostCount &&
        left.completedBookingMilestoneCount ==
            right.completedBookingMilestoneCount &&
        left.completedBookingMilestoneUnlocked ==
            right.completedBookingMilestoneUnlocked &&
        left.secondSocialPostMilestoneUnlocked ==
            right.secondSocialPostMilestoneUnlocked &&
        left.appOpenFallbackMilestoneUnlocked ==
            right.appOpenFallbackMilestoneUnlocked &&
        left.pendingOpportunity == right.pendingOpportunity &&
        left.pendingOpportunitySource == right.pendingOpportunitySource &&
        left.requestCount == right.requestCount &&
        _datesEqual(left.lastRequestedAt, right.lastRequestedAt);
  }

  bool _datesEqual(DateTime? left, DateTime? right) {
    if (left == null && right == null) return true;
    if (left == null || right == null) return false;
    return left.isAtSameMomentAs(right);
  }
}
