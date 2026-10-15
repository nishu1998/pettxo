import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/services/permission_prompt_coordinator.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../messages/data/repositories/chat_repository.dart';
import '../../../messages/presentation/screens/chat_detail_screen.dart';
import '../../../provider/data/repositories/provider_onboarding_repository.dart';
import '../../../provider/domain/models/provider_onboarding_models.dart';
import '../../../profile/data/repositories/pet_repository.dart';
import '../../../profile/data/repositories/profile_content_repository.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/pet_profile.dart';
import '../../../profile/domain/models/profile_service_listing.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../profile/presentation/screens/add_edit_pet_screen.dart';
import '../../../profile/presentation/widgets/profile_content_sections.dart';
import '../../../profile/presentation/widgets/profile_guided_tour.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../../services/data/repositories/services_repository.dart';
import '../../../settings/data/services/settings_service.dart';
import '../../../settings/domain/models/app_settings.dart';
import '../../../social/data/follow_repository.dart';
import '../../../social/domain/models/social_post_model.dart';
import '../../../social/presentation/screens/user_list_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;

  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileTourReadinessSignal extends ChangeNotifier {
  bool get isObserved => hasListeners;

  void signal() => notifyListeners();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Map<String, ProfileFollowCounts> _followCountCache =
      <String, ProfileFollowCounts>{};
  final Map<String, ProfileFollowCounts> _observedProjectedCounts =
      <String, ProfileFollowCounts>{};

  final ProfileRepository _profileRepository = ProfileRepository();
  final PetRepository _petRepository = PetRepository();
  final ProfileContentRepository _contentRepository =
      ProfileContentRepository();
  final ServicesRepository _servicesRepository = ServicesRepository();
  final ProviderOnboardingRepository _providerOnboardingRepository =
      ProviderOnboardingRepository();
  final SettingsService _settingsService = SettingsService();
  final FollowRepository _followRepository = FollowRepository();
  final ChatRepository _chatRepository = ChatRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final ScrollController _profileScrollController;
  final ScrollController _petsTourScrollController = ScrollController();
  final _ProfileTourReadinessSignal _profileTourReadiness =
      _ProfileTourReadinessSignal();
  final ProfileTourTargetHandle _profileTourSettingsTargetKey =
      ProfileTourTargetHandle();
  final ProfileTourTargetHandle _profileTourBookingsTargetKey =
      ProfileTourTargetHandle();
  final ProfileTourTargetHandle _profileTourAddPetTargetKey =
      ProfileTourTargetHandle();
  final ProfileTourTargetHandle _profileTourPostsTargetKey =
      ProfileTourTargetHandle();
  final ProfileTourTargetHandle _profileTourServicesTargetKey =
      ProfileTourTargetHandle();
  final ProfileTourTargetHandle _profileTourAddServiceTargetKey =
      ProfileTourTargetHandle();
  final ProfileGuidedTourController _profileTourController =
      ProfileGuidedTourController();
  late Future<AppSettings> _settingsFuture;
  int _selectedSectionIndex = 0;
  bool _showProfileSpotlight = false;
  String _followTargetUserId = '';
  Future<bool>? _followStateFuture;
  bool? _followStateOverride;
  bool _isFollowActionRunning = false;
  bool _isOpeningDirectChat = false;
  bool _isGlobalServiceActionRunning = false;
  String _runningServiceActionId = '';
  final Map<String, Future<ProfileFollowCounts>> _followCountRequests =
      <String, Future<ProfileFollowCounts>>{};
  final Map<String, Future<bool>> _providerVerificationRequests =
      <String, Future<bool>>{};
  StreamSubscription<FollowChange>? _followChangeSubscription;
  StreamSubscription<User?>? _profileTourAuthSubscription;
  String _profileTourUid = '';
  bool _profileTourLaunchInFlight = false;
  bool _profileTourActive = false;
  bool _profileTourLayoutPrepared = false;
  bool _profileTourDisposing = false;
  bool _profileTourReadinessSignalScheduled = false;

  @override
  void initState() {
    super.initState();
    _profileScrollController = ScrollController(
      onAttach: _handleProfileScrollAttach,
      onDetach: _handleProfileScrollDetach,
    );
    for (final target in _profileTourTargetHandles) {
      target.addListener(_signalProfileTourReadiness);
    }
    _settingsFuture = _loadInitialSettings();
    _followChangeSubscription = _followRepository.changes.listen(
      _handleCanonicalFollowChange,
    );
    _profileTourUid = _auth.currentUser?.uid.trim() ?? '';
    _profileTourAuthSubscription = _auth.authStateChanges().listen(
      _handleProfileTourAuthChanged,
    );
    _profileTourController.isActive.addListener(
      _handleProfileTourActiveChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startProfileTour());
    });
  }

  @override
  void dispose() {
    _profileTourDisposing = true;
    _profileTourReadiness.signal();
    _profileTourController.isActive.removeListener(
      _handleProfileTourActiveChanged,
    );
    _profileTourController.dispose();
    for (final target in _profileTourTargetHandles) {
      target.removeListener(_signalProfileTourReadiness);
    }
    _profileTourAuthSubscription?.cancel();
    _profileScrollController.dispose();
    _petsTourScrollController.dispose();
    _followChangeSubscription?.cancel();
    _profileTourReadiness.dispose();
    super.dispose();
  }

  Iterable<ProfileTourTargetHandle> get _profileTourTargetHandles =>
      <ProfileTourTargetHandle>[
        _profileTourSettingsTargetKey,
        _profileTourBookingsTargetKey,
        _profileTourAddPetTargetKey,
        _profileTourPostsTargetKey,
        _profileTourServicesTargetKey,
        _profileTourAddServiceTargetKey,
      ];

  void _handleProfileScrollAttach(ScrollPosition position) {
    position.addListener(_signalProfileTourReadiness);
    _signalProfileTourReadiness();
  }

  void _handleProfileScrollDetach(ScrollPosition position) {
    position.removeListener(_signalProfileTourReadiness);
    _signalProfileTourReadiness();
  }

  void _signalProfileTourReadiness() {
    if (_profileTourDisposing ||
        !_profileTourReadiness.isObserved ||
        _profileTourReadinessSignalScheduled) {
      return;
    }
    _profileTourReadinessSignalScheduled = true;
    scheduleMicrotask(() {
      _profileTourReadinessSignalScheduled = false;
      if (_profileTourDisposing) return;
      _profileTourReadiness.signal();
    });
  }

  void _handleProfileTourActiveChanged() {
    final active = _profileTourController.isActive.value;
    _signalProfileTourReadiness();
    if (!mounted || active == _profileTourActive) return;
    setState(() => _profileTourActive = active);
  }

  bool get _isOwnProfileForTour {
    final currentUid = _auth.currentUser?.uid.trim() ?? '';
    final requestedUid = widget.userId?.trim() ?? '';
    return currentUid.isNotEmpty &&
        (requestedUid.isEmpty || requestedUid == currentUid);
  }

  ProfileTourTargets get _profileTourTargets => ProfileTourTargets(
    settings: _profileTourSettingsTargetKey,
    bookings: _profileTourBookingsTargetKey,
    addPet: _profileTourAddPetTargetKey,
    postsTab: _profileTourPostsTargetKey,
    servicesTab: _profileTourServicesTargetKey,
    addService: _profileTourAddServiceTargetKey,
  );

  void _handleProfileTourAuthChanged(User? user) {
    final nextUid = user?.uid.trim() ?? '';
    if (nextUid == _profileTourUid) return;
    _profileTourUid = nextUid;
    _profileTourController.cancel();
    if (nextUid.isNotEmpty && _isOwnProfileForTour) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_startProfileTour());
      });
    }
  }

  Future<void> _startProfileTour() async {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    if (!mounted ||
        uid.isEmpty ||
        !_isOwnProfileForTour ||
        _profileTourLaunchInFlight) {
      return;
    }
    _profileTourLaunchInFlight = true;
    final originalSectionIndex = _selectedSectionIndex;
    final originalProfileOffset = _profileScrollController.hasClients
        ? _profileScrollController.offset
        : 0.0;
    final originalPetsOffset = _petsTourScrollController.hasClients
        ? _petsTourScrollController.offset
        : 0.0;
    try {
      final result = await PermissionPromptCoordinator.instance.run(() async {
        if (!mounted ||
            uid != (_auth.currentUser?.uid.trim() ?? '') ||
            !_isOwnProfileForTour) {
          return null;
        }
        if (!await _waitForProfileTourRouteReady(uid)) {
          return null;
        }
        if (!mounted) return null;
        return _profileTourController.start(
          context: context,
          uid: uid,
          targets: _profileTourTargets,
          beforeShow: _prepareProfileTour,
          prepareInitial: _prepareProfileTourInitialTarget,
          prepareStep: _prepareProfileTourStep,
        );
      });
      if (result != null && mounted) {
        await _restoreProfileTourState(
          sectionIndex: originalSectionIndex,
          profileOffset: originalProfileOffset,
          petsOffset: originalPetsOffset,
        );
      }
    } finally {
      _profileTourLaunchInFlight = false;
      if (mounted && _profileTourLayoutPrepared) {
        setState(() => _profileTourLayoutPrepared = false);
      }
    }
  }

  Future<bool> _waitForProfileTourRouteReady(String uid) async {
    for (var attempt = 0; attempt < 40; attempt += 1) {
      if (!mounted ||
          uid != (_auth.currentUser?.uid.trim() ?? '') ||
          !_isOwnProfileForTour) {
        return false;
      }
      final route = ModalRoute.of(context);
      final targetsReady =
          _profileTourSettingsTargetKey.isAvailable &&
          _profileTourBookingsTargetKey.isAvailable;
      if ((route == null || route.isCurrent) && targetsReady) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<void> _prepareProfileTour() async {
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (!_profileTourLayoutPrepared) {
      setState(() => _profileTourLayoutPrepared = true);
    }
    await WidgetsBinding.instance.endOfFrame;
    _signalProfileTourReadiness();
  }

  Future<bool> _prepareProfileTourInitialTarget() async {
    final ready = await _waitForProfileTourScrollMetrics(
      currentStep: 0,
      requestedNextStep: 0,
      target: _profileTourSettingsTargetKey,
      canContinue: _canContinueProfileTourStartup,
      timeout: const Duration(seconds: 8),
    );
    if (!ready || !mounted || !_canContinueProfileTourStartup()) {
      return false;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_canContinueProfileTourStartup()) return false;
    final targetRect = measureProfileTourTarget(_profileTourSettingsTargetKey);
    final valid =
        targetRect != null &&
        isProfileTourInitialTargetReady(
          targetRect: targetRect,
          viewportSize: MediaQuery.sizeOf(context),
          safePadding: MediaQuery.paddingOf(context),
        );
    return valid;
  }

  Future<bool> _prepareProfileTourStep(int stepIndex) async {
    final target = _profileTourTargetForStep(stepIndex);
    final originalSectionIndex = _selectedSectionIndex;
    var sectionChanged = false;
    if (!_canContinueProfileTourPreparation()) {
      return false;
    }
    if (stepIndex == 3 && _selectedSectionIndex != 0) {
      setState(() => _selectedSectionIndex = 0);
      sectionChanged = true;
      await WidgetsBinding.instance.endOfFrame;
    } else if (stepIndex >= 4 && _selectedSectionIndex != 1) {
      setState(() => _selectedSectionIndex = 1);
      sectionChanged = true;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!_canContinueProfileTourPreparation()) {
      return false;
    }
    if (stepIndex == 2) {
      for (var attempt = 0; attempt < 3; attempt += 1) {
        await WidgetsBinding.instance.endOfFrame;
        if (!_canContinueProfileTourPreparation()) {
          return false;
        }
        if (!_petsTourScrollController.hasClients) {
          continue;
        }
        final maxOffset = _petsTourScrollController.position.maxScrollExtent;
        if ((_petsTourScrollController.offset - maxOffset).abs() >= 0.5) {
          await _petsTourScrollController.animateTo(
            maxOffset,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
          );
        }
        break;
      }
    }

    if (!mounted || !_canContinueProfileTourPreparation()) return false;
    final scrollReady = await _waitForProfileTourScrollMetrics(
      currentStep: stepIndex - 1,
      requestedNextStep: stepIndex,
      target: target,
    );
    if (!scrollReady || !mounted || !_canContinueProfileTourPreparation()) {
      await _recoverProfileTourSectionAfterFailedTransition(
        stepIndex: stepIndex,
        originalSectionIndex: originalSectionIndex,
        sectionChanged: sectionChanged,
        reason: 'scroll_readiness_failed',
      );
      return false;
    }
    final layoutSnapshot = _profileTourController.layoutSnapshot.value;
    if (layoutSnapshot == null || layoutSnapshot.stepIndex != stepIndex) {
      await _recoverProfileTourSectionAfterFailedTransition(
        stepIndex: stepIndex,
        originalSectionIndex: originalSectionIndex,
        sectionChanged: sectionChanged,
        reason: 'shared_geometry_unavailable',
      );
      return false;
    }
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final revealed = await revealProfileTourTarget(
      context: context,
      scrollController: _profileScrollController,
      targetKey: target,
      headerBottom: MediaQuery.paddingOf(context).top + 74,
      bottomObstruction: viewportHeight < 650 ? 258 : 280,
      spotlightPadding: stepIndex == 2 ? 5 : 6,
      usableViewport: layoutSnapshot.usableViewport,
      canContinue: _canContinueProfileTourPreparation,
    );
    if (!revealed) {
      await _recoverProfileTourSectionAfterFailedTransition(
        stepIndex: stepIndex,
        originalSectionIndex: originalSectionIndex,
        sectionChanged: sectionChanged,
        reason: 'target_reveal_failed',
      );
    }
    return revealed;
  }

  ProfileTourTargetHandle _profileTourTargetForStep(int stepIndex) {
    return switch (stepIndex) {
      1 => _profileTourBookingsTargetKey,
      2 => _profileTourAddPetTargetKey,
      3 => _profileTourPostsTargetKey,
      4 => _profileTourServicesTargetKey,
      5 => _profileTourAddServiceTargetKey,
      _ => _profileTourSettingsTargetKey,
    };
  }

  Future<void> _recoverProfileTourSectionAfterFailedTransition({
    required int stepIndex,
    required int originalSectionIndex,
    required bool sectionChanged,
    required String reason,
  }) async {
    if (!sectionChanged || !mounted || !_canContinueProfileTourPreparation()) {
      return;
    }
    setState(() => _selectedSectionIndex = originalSectionIndex);
    await WidgetsBinding.instance.endOfFrame;
    _signalProfileTourReadiness();
    final previousTarget = _profileTourTargetForStep(stepIndex - 1);
    await _waitForProfileTourScrollMetrics(
      currentStep: stepIndex - 1,
      requestedNextStep: stepIndex - 1,
      target: previousTarget,
      timeout: const Duration(seconds: 3),
    );
  }

  Future<bool> _waitForProfileTourScrollMetrics({
    required int currentStep,
    required int requestedNextStep,
    required ProfileTourTargetHandle target,
    bool Function()? canContinue,
    Duration timeout = const Duration(seconds: 10),
  }) {
    final sessionGuard = canContinue ?? _canContinueProfileTourPreparation;
    return waitForProfileTourReadiness(
      readinessSignal: _profileTourReadiness,
      scrollController: _profileScrollController,
      target: target,
      canContinue: () => mounted && !_profileTourDisposing && sessionGuard(),
      timeout: timeout,
    );
  }

  bool _canContinueProfileTourPreparation() {
    return mounted &&
        !_profileTourDisposing &&
        _profileTourController.isActive.value &&
        _isOwnProfileForTour &&
        _profileTourUid == (_auth.currentUser?.uid.trim() ?? '');
  }

  bool _canContinueProfileTourStartup() {
    if (!mounted ||
        _profileTourDisposing ||
        !_profileTourLaunchInFlight ||
        !_isOwnProfileForTour ||
        _profileTourUid != (_auth.currentUser?.uid.trim() ?? '')) {
      return false;
    }
    final route = ModalRoute.of(context);
    return route == null || route.isCurrent;
  }

  Future<void> _restoreProfileTourState({
    required int sectionIndex,
    required double profileOffset,
    required double petsOffset,
  }) async {
    if (!mounted) return;
    if (_selectedSectionIndex != sectionIndex) {
      setState(() => _selectedSectionIndex = sectionIndex);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (_profileScrollController.hasClients) {
      _profileScrollController.jumpTo(
        profileOffset.clamp(
          _profileScrollController.position.minScrollExtent,
          _profileScrollController.position.maxScrollExtent,
        ),
      );
    }
    if (_petsTourScrollController.hasClients) {
      _petsTourScrollController.jumpTo(
        petsOffset.clamp(
          _petsTourScrollController.position.minScrollExtent,
          _petsTourScrollController.position.maxScrollExtent,
        ),
      );
    }
  }

  Future<AppSettings> _loadInitialSettings() async {
    final settings = await _settingsService.loadSettings();

    // The spotlight is meant to be a one-time helper. We persist that the user
    // has seen it in local settings, but keep it visible for the current visit.
    if (!settings.hasSeenProfileSpotlight) {
      _showProfileSpotlight = true;
      final updatedSettings = settings.copyWith(hasSeenProfileSpotlight: true);
      await _settingsService.saveSettings(updatedSettings);
      return updatedSettings;
    }

    return settings;
  }

  Future<void> _refreshSettings() async {
    setState(() {
      _settingsFuture = _settingsService.loadSettings();
    });
  }

  Future<ProfileFollowCounts> _requestFollowCounts(String userId) {
    final trimmedUserId = userId.trim();
    return _followCountRequests.putIfAbsent(
      trimmedUserId,
      () => _followRepository.fetchProfileFollowCounts(trimmedUserId),
    );
  }

  Future<bool> _requestProviderVerified(String userId) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return Future<bool>.value(false);

    return _providerVerificationRequests.putIfAbsent(trimmedUserId, () async {
      try {
        final verification = await _providerOnboardingRepository
            .fetchVerificationForUser(trimmedUserId, forceServer: true);
        return verification.status == providerVerificationApproved;
      } catch (_) {
        return false;
      }
    });
  }

  void _ensureFollowCountsLoaded(String userId, {bool forceRefresh = false}) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return;

    if (forceRefresh) {
      _followCountRequests.remove(trimmedUserId);
    } else if (_followCountCache.containsKey(trimmedUserId) ||
        _followCountRequests.containsKey(trimmedUserId)) {
      return;
    }

    _requestFollowCounts(trimmedUserId)
        .then((counts) {
          _followCountRequests.remove(trimmedUserId);
          final previous = _followCountCache[trimmedUserId];
          final didChange =
              previous?.followerCount != counts.followerCount ||
              previous?.followingCount != counts.followingCount;
          _followCountCache[trimmedUserId] = counts;
          if (!mounted || !didChange) return;
          setState(() {});
        })
        .catchError((_) {
          _followCountRequests.remove(trimmedUserId);
          // Keep the last visible counts if refresh fails.
        });
  }

  void _handleCanonicalFollowChange(FollowChange change) {
    _ensureFollowCountsLoaded(change.followerId, forceRefresh: true);
    _ensureFollowCountsLoaded(change.followeeId, forceRefresh: true);
  }

  void _observeProjectedFollowCounts(UserProfile profile) {
    final projected = ProfileFollowCounts(
      followerCount: profile.followerCount,
      followingCount: profile.followingCount,
    );
    final previous = _observedProjectedCounts[profile.uid];
    if (previous?.followerCount == projected.followerCount &&
        previous?.followingCount == projected.followingCount) {
      _ensureFollowCountsLoaded(profile.uid);
      return;
    }
    _observedProjectedCounts[profile.uid] = projected;
    _ensureFollowCountsLoaded(profile.uid, forceRefresh: true);
  }

  void _syncFollowState({
    required String currentUserId,
    required String profileUserId,
    required bool isOwnProfile,
  }) {
    if (isOwnProfile || currentUserId.isEmpty) {
      _followTargetUserId = '';
      _followStateFuture = null;
      _followStateOverride = null;
      return;
    }

    if (_followTargetUserId == profileUserId && _followStateFuture != null) {
      return;
    }

    _followTargetUserId = profileUserId;
    _followStateFuture = _followRepository.isFollowing(
      followerId: currentUserId,
      followeeId: profileUserId,
    );
    _followStateOverride = null;
  }

  Future<void> _toggleFollow({
    required String currentUserId,
    required UserProfile profile,
    required bool currentlyFollowing,
  }) async {
    if (_isFollowActionRunning) return;
    if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }

    final previous = currentlyFollowing;
    final previousOverride = _followStateOverride;
    setState(() {
      _isFollowActionRunning = true;
      _followStateOverride = !previous;
    });

    try {
      final resolved = await _followRepository.toggleFollow(
        followerId: currentUserId,
        followeeId: profile.uid,
        currentlyFollowing: previous,
      );
      if (!mounted) return;
      setState(() {
        _followStateOverride = resolved;
      });
      _ensureFollowCountsLoaded(profile.uid, forceRefresh: true);
      _ensureFollowCountsLoaded(currentUserId, forceRefresh: true);
      AppFeedback.show(
        context,
        message: resolved ? 'Followed user.' : 'Unfollowed user.',
        tone: AppFeedbackTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _followStateOverride = previousOverride;
      });
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isFollowActionRunning = false);
      }
    }
  }

  Future<void> _openDirectChat({
    required UserProfile profile,
    required String currentUserId,
  }) async {
    if (_isOpeningDirectChat || currentUserId.isEmpty) return;
    if (profile.uid == currentUserId) {
      AppFeedback.show(
        context,
        message: 'You cannot message yourself.',
        tone: AppFeedbackTone.error,
      );
      return;
    }
    if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }

    final orderedIds = [currentUserId.trim(), profile.uid.trim()]..sort();
    final deterministicChatId = 'chat_${orderedIds.join('_')}';
    if (kDebugMode) {
      debugPrint(
        'Profile Message debug -> profileUserId=${profile.uid}, '
        'currentUserId=$currentUserId, '
        'deterministicChatId=$deterministicChatId',
      );
    }

    setState(() => _isOpeningDirectChat = true);
    try {
      final chatId = await _chatRepository.startDirectUserChat(
        otherUserId: profile.uid,
      );
      if (kDebugMode) {
        debugPrint('Profile Message debug -> opened chatId=$chatId');
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatDetailScreen(chatId: chatId)),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Profile Message debug -> exception=$error\n$stackTrace');
      }
      if (!mounted) return;
      final raw = error.toString();
      final message = raw.contains('message yourself')
          ? 'You cannot message yourself.'
          : raw.contains('cannot start chats')
          ? 'Your account cannot start chats right now.'
          : raw.contains('unavailable for chat')
          ? 'This user is unavailable for chat right now.'
          : 'Unable to open chat right now.';
      AppFeedback.show(context, message: message, tone: AppFeedbackTone.error);
    } finally {
      if (mounted) {
        setState(() => _isOpeningDirectChat = false);
      }
    }
  }

  Future<void> _setProfileServicePaused(
    ProfileServiceListing service,
    bool isPaused,
  ) async {
    if (_runningServiceActionId.isNotEmpty) return;
    setState(() => _runningServiceActionId = service.id);
    try {
      await _servicesRepository.setServicePaused(service.id, isPaused);
      if (!mounted) return;
      setState(() {});
      AppFeedback.show(
        context,
        message: isPaused ? 'Service paused.' : 'Service resumed.',
        tone: AppFeedbackTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: isPaused
            ? 'Unable to pause service right now.'
            : 'Unable to resume service right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted && _runningServiceActionId == service.id) {
        setState(() => _runningServiceActionId = '');
      }
    }
  }

  Future<void> _deleteProfileService(ProfileServiceListing service) async {
    if (_runningServiceActionId.isNotEmpty) return;
    setState(() => _runningServiceActionId = service.id);
    try {
      await _servicesRepository.deleteService(service.id);
      if (!mounted) return;
      setState(() {});
      AppFeedback.show(
        context,
        message: 'Service removed from your profile.',
        tone: AppFeedbackTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Unable to remove service right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted && _runningServiceActionId == service.id) {
        setState(() => _runningServiceActionId = '');
      }
    }
  }

  Future<void> _toggleAllProfileServices(
    List<ProfileServiceListing> services,
    bool pause,
  ) async {
    if (_isGlobalServiceActionRunning) return;
    final eligibleServices = services
        .where((service) => !service.isPausedByVerification)
        .toList(growable: false);
    final targets = eligibleServices
        .where((service) => pause ? !service.isPaused : service.isPaused)
        .toList(growable: false);
    if (targets.isEmpty) return;

    setState(() => _isGlobalServiceActionRunning = true);
    try {
      for (final service in targets) {
        await _servicesRepository.setServicePaused(service.id, pause);
      }
      if (!mounted) return;
      setState(() {});
      AppFeedback.show(
        context,
        message: pause
            ? 'All eligible services are paused.'
            : 'All eligible services are active.',
        tone: AppFeedbackTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: pause
            ? 'Unable to pause all services right now.'
            : 'Unable to resume all services right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isGlobalServiceActionRunning = false);
      }
    }
  }

  Widget _buildProfileStatsRow({
    required BuildContext context,
    required int postsCount,
    required int followerCount,
    required int followingCount,
    required bool isOwnProfile,
    required String profileUserId,
  }) {
    return Row(
      children: [
        Expanded(
          child: _ProfileStat(label: "posts", value: "$postsCount"),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _ProfileStat(
            label: "followers",
            value: "$followerCount",
            onTap: isOwnProfile
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserListScreen(
                        title: 'Followers',
                        emptyMessage: 'No followers yet',
                        listKind: UserListKind.followers,
                        loader: (lastDoc) =>
                            _followRepository.fetchFollowerIdsPage(
                              userId: profileUserId,
                              lastDoc: lastDoc,
                            ),
                      ),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _ProfileStat(
            label: "following",
            value: "$followingCount",
            onTap: isOwnProfile
                ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserListScreen(
                        title: 'Following',
                        emptyMessage: 'Not following anyone yet',
                        listKind: UserListKind.following,
                        loader: (lastDoc) =>
                            _followRepository.fetchFollowingIdsPage(
                              userId: profileUserId,
                              lastDoc: lastDoc,
                            ),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final requestedUserId = widget.userId?.trim() ?? '';
    final isOwnProfile =
        requestedUserId.isEmpty || requestedUserId == currentUserId;
    final topInset = mediaQuery.padding.top;
    const topBarHeight = 74.0;
    final topContentPadding = topInset + topBarHeight;
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);
    final tourScrollSpacer = (_profileTourActive || _profileTourLayoutPrepared)
        ? calculateProfileTourScrollSpacer(
            viewportHeight: mediaQuery.size.height,
            normalBottomPadding: bottomContentPadding,
          )
        : 0.0;
    return ProfileTourBackScope(
      isTourActive: _profileTourActive,
      onDismissTour: () {
        _profileTourController.cancel();
      },
      child: SocialTabBackScope(
        activeTab: SocialAppTab.profile,
        enabled: isOwnProfile && !_profileTourActive,
        child: Scaffold(
          backgroundColor: AppColors.background,
          extendBody: true,
          body: FutureBuilder<AppSettings>(
            future: _settingsFuture,
            builder: (context, settingsSnapshot) {
              if (!settingsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              return StreamBuilder<UserProfile>(
                stream: isOwnProfile
                    ? _profileRepository.watchCurrentUserProfile()
                    : _profileRepository.watchUserProfile(requestedUserId),
                builder: (context, profileSnapshot) {
                  if (profileSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (profileSnapshot.hasError || !profileSnapshot.hasData) {
                    return const _ProfileErrorState();
                  }

                  final profile = profileSnapshot.data!;
                  if (!isOwnProfile && !profile.isPubliclyVisible) {
                    return const _ProfileUnavailableState();
                  }
                  _syncFollowState(
                    currentUserId: currentUserId,
                    profileUserId: profile.uid,
                    isOwnProfile: isOwnProfile,
                  );
                  _observeProjectedFollowCounts(profile);
                  final cachedCounts = _followCountCache[profile.uid];

                  return StreamBuilder<List<ProfileServiceListing>>(
                    stream:
                        (isOwnProfile
                                ? _servicesRepository.watchOwnerServices(
                                    profile.uid,
                                  )
                                : _servicesRepository.watchPublicOwnerServices(
                                    profile.uid,
                                  ))
                            .map((services) => services.toProfileListings()),
                    builder: (context, servicesSnapshot) {
                      final services = servicesSnapshot.data ?? const [];
                      final hasApprovedProviderVerification = services.any(
                        (service) =>
                            service.providerVerificationStatus ==
                            providerVerificationApproved,
                      );
                      final selectedSectionIndex = _selectedSectionIndex;

                      return StreamBuilder<List<PetProfile>>(
                        stream: _petRepository.watchVisiblePets(profile.uid),
                        builder: (context, petsSnapshot) {
                          final pets =
                              petsSnapshot.data ?? const <PetProfile>[];

                          return StreamBuilder<List<SocialPostModel>>(
                            stream: _contentRepository.watchPostsForProfile(
                              profile,
                            ),
                            builder: (context, postsSnapshot) {
                              final posts =
                                  postsSnapshot.data ??
                                  const <SocialPostModel>[];

                              return Stack(
                                children: [
                                  // The profile list fills the screen first so cards can
                                  // move behind the glass header and bottom nav overlays.
                                  NotificationListener<
                                    ScrollMetricsNotification
                                  >(
                                    onNotification: (notification) {
                                      _signalProfileTourReadiness();
                                      return false;
                                    },
                                    child: ListView(
                                      controller: _profileScrollController,
                                      padding: EdgeInsets.fromLTRB(
                                        18,
                                        topContentPadding,
                                        18,
                                        bottomContentPadding + tourScrollSpacer,
                                      ),
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.fromLTRB(
                                            14,
                                            12,
                                            14,
                                            14,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              28,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  _ProfileAvatar(
                                                    imageUrl:
                                                        profile.profileImageUrl,
                                                    fallbackInitials:
                                                        profile.initials,
                                                    size: 96,
                                                  ),
                                                  const SizedBox(width: 18),
                                                  Expanded(
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            top: 2,
                                                          ),
                                                      child: _buildProfileStatsRow(
                                                        context: context,
                                                        postsCount:
                                                            posts.length,
                                                        followerCount:
                                                            cachedCounts
                                                                ?.followerCount ??
                                                            profile
                                                                .followerCount,
                                                        followingCount:
                                                            cachedCounts
                                                                ?.followingCount ??
                                                            profile
                                                                .followingCount,
                                                        isOwnProfile:
                                                            isOwnProfile,
                                                        profileUserId:
                                                            profile.uid,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Text(
                                                profile.name.isEmpty
                                                    ? 'Your Name'
                                                    : profile.name,
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.textDark,
                                                  letterSpacing: -0.3,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              _ProfileBadges(
                                                roleLabel: profile.roleLabel,
                                                isServiceProvider:
                                                    profile.isServiceProvider,
                                                isVerifiedFallback:
                                                    hasApprovedProviderVerification,
                                                verifiedFuture:
                                                    _requestProviderVerified(
                                                      profile.uid,
                                                    ),
                                              ),
                                              if (profile
                                                  .isServiceProvider) ...[
                                                const SizedBox(height: 6),
                                                Text(
                                                  profile.providerReviewSummary,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: profile.hasReviews
                                                        ? const Color(
                                                            0xFF9A3412,
                                                          )
                                                        : AppColors.textGrey,
                                                    fontSize: 13.5,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 8),
                                              if (profile.bio.isNotEmpty ||
                                                  isOwnProfile) ...[
                                                Text(
                                                  profile.bio.isEmpty
                                                      ? 'Tell people a little about you from Settings > Profile details.'
                                                      : profile.bio,
                                                  style: TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500,
                                                    color: profile.bio.isEmpty
                                                        ? AppColors.textGrey
                                                        : AppColors.textDark,
                                                    height: 1.32,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                              ],
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.location_on_outlined,
                                                    color: AppColors.textGrey,
                                                    size: 18,
                                                  ),
                                                  const SizedBox(width: 7),
                                                  Expanded(
                                                    child: Text(
                                                      profile.location.isEmpty
                                                          ? 'Add your location in profile settings'
                                                          : profile.location,
                                                      style: const TextStyle(
                                                        color:
                                                            AppColors.textGrey,
                                                        fontSize: 13.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        height: 1.15,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 14),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: isOwnProfile
                                                        ? _ProfileActionButton(
                                                            label:
                                                                'Edit profile',
                                                            isPrimary: false,
                                                            onPressed: () async {
                                                              await Navigator.pushNamed(
                                                                context,
                                                                "/settings/profile",
                                                              );
                                                            },
                                                          )
                                                        : FutureBuilder<bool>(
                                                            future:
                                                                _followStateFuture,
                                                            builder:
                                                                (
                                                                  context,
                                                                  followSnapshot,
                                                                ) {
                                                                  final isFollowing =
                                                                      _followStateOverride ??
                                                                      followSnapshot
                                                                          .data ??
                                                                      false;
                                                                  final onPressed =
                                                                      currentUserId
                                                                              .isEmpty ||
                                                                          followSnapshot.connectionState ==
                                                                              ConnectionState.waiting
                                                                      ? null
                                                                      : () => _toggleFollow(
                                                                          currentUserId:
                                                                              currentUserId,
                                                                          profile:
                                                                              profile,
                                                                          currentlyFollowing:
                                                                              isFollowing,
                                                                        );
                                                                  final label =
                                                                      _isFollowActionRunning
                                                                      ? 'Updating...'
                                                                      : (isFollowing
                                                                            ? 'Following'
                                                                            : 'Follow');

                                                                  return isFollowing
                                                                      ? SecondaryButton(
                                                                          label:
                                                                              label,
                                                                          size:
                                                                              AppButtonSize.compact,
                                                                          onPressed:
                                                                              onPressed,
                                                                        )
                                                                      : GradientButton(
                                                                          label:
                                                                              label,
                                                                          size:
                                                                              AppButtonSize.compact,
                                                                          onPressed:
                                                                              onPressed,
                                                                        );
                                                                },
                                                          ),
                                                  ),
                                                  const SizedBox(width: 14),
                                                  Expanded(
                                                    child: isOwnProfile
                                                        ? ProfileTourTarget(
                                                            handle:
                                                                _profileTourBookingsTargetKey,
                                                            child: _ProfileActionButton(
                                                              label: 'Bookings',
                                                              isPrimary: true,
                                                              onPressed: () {
                                                                Navigator.pushNamed(
                                                                  context,
                                                                  "/bookings",
                                                                );
                                                              },
                                                            ),
                                                          )
                                                        : SecondaryButton(
                                                            label:
                                                                _isOpeningDirectChat
                                                                ? "Opening..."
                                                                : "Message",
                                                            size: AppButtonSize
                                                                .compact,
                                                            onPressed:
                                                                currentUserId
                                                                    .isEmpty
                                                                ? null
                                                                : () => _openDirectChat(
                                                                    profile:
                                                                        profile,
                                                                    currentUserId:
                                                                        currentUserId,
                                                                  ),
                                                          ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (isOwnProfile &&
                                            _showProfileSpotlight) ...[
                                          const SizedBox(height: 18),
                                          Container(
                                            padding: const EdgeInsets.all(18),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  AppColors.primary.withValues(
                                                    alpha: 0.08,
                                                  ),
                                                  Colors.white,
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              border: Border.all(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.08),
                                              ),
                                            ),
                                            child: const Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        "Profile spotlight",
                                                        style: TextStyle(
                                                          color:
                                                              AppColors.primary,
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      SizedBox(height: 6),
                                                      Text(
                                                        "Showcase both personality and services so followers can trust you before they book.",
                                                        style: TextStyle(
                                                          color: AppColors
                                                              .textDark,
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          height: 1.45,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                SizedBox(width: 12),
                                                Icon(
                                                  Icons
                                                      .workspace_premium_outlined,
                                                  color: AppColors.primary,
                                                  size: 28,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        if (isOwnProfile ||
                                            pets.isNotEmpty) ...[
                                          const SizedBox(height: 18),
                                          ProfilePetsSection(
                                            pets: pets,
                                            canAddPet: isOwnProfile,
                                            addPetTargetKey:
                                                _profileTourAddPetTargetKey,
                                            scrollController:
                                                _petsTourScrollController,
                                            onAddPet: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      AddEditPetScreen(
                                                        ownerId: profile.uid,
                                                      ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                        const SizedBox(height: 6),
                                        ProfileSectionTabs(
                                          selectedIndex: selectedSectionIndex,
                                          showServices: true,
                                          serviceCount: services.length,
                                          postsTargetKey:
                                              _profileTourPostsTargetKey,
                                          servicesTargetKey:
                                              _profileTourServicesTargetKey,
                                          onChanged: (index) {
                                            setState(() {
                                              _selectedSectionIndex = index;
                                            });
                                          },
                                        ),
                                        const SizedBox(height: 0),
                                        if (selectedSectionIndex == 0)
                                          ProfilePostsSection(
                                            posts: posts,
                                            canCreatePost: isOwnProfile,
                                            currentUserId: currentUserId,
                                          )
                                        else
                                          ProfileServicesSection(
                                            services: services,
                                            canManage: isOwnProfile,
                                            addServiceTargetKey:
                                                _profileTourAddServiceTargetKey,
                                            onAdd: () async {
                                              if (!UserRestrictionService
                                                  .instance
                                                  .ensureCanUseBookingFeatures(
                                                    context,
                                                  )) {
                                                return;
                                              }
                                              final added =
                                                  await Navigator.pushNamed(
                                                    context,
                                                    "/profile/services/add",
                                                  );
                                              if (!mounted) return;
                                              if (added == true) {
                                                setState(() {
                                                  _selectedSectionIndex = 1;
                                                });
                                              }
                                            },
                                            isGlobalActionRunning:
                                                _isGlobalServiceActionRunning,
                                            runningServiceActionId:
                                                _runningServiceActionId,
                                            onToggleAll: (pause) =>
                                                _toggleAllProfileServices(
                                                  services,
                                                  pause,
                                                ),
                                            onPauseService: (service) =>
                                                _setProfileServicePaused(
                                                  service,
                                                  true,
                                                ),
                                            onResumeService: (service) =>
                                                _setProfileServicePaused(
                                                  service,
                                                  false,
                                                ),
                                            onDeleteService:
                                                _deleteProfileService,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: 0,
                                    child: GlassSurface(
                                      padding: const EdgeInsets.fromLTRB(
                                        18,
                                        0,
                                        18,
                                        10,
                                      ),
                                      borderRadius: BorderRadius.circular(0),
                                      backgroundColor: Colors.white.withValues(
                                        alpha: 0.42,
                                      ),
                                      blurSigma: 20,
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                      ),
                                      boxShadow: const [],
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          Padding(
                                            padding: EdgeInsets.only(
                                              top: topInset + 6,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                    gradient: isOwnProfile
                                                        ? const LinearGradient(
                                                            colors: [
                                                              Color(0xFFFFE9DD),
                                                              Color(0xFFFFF3EC),
                                                            ],
                                                            begin: Alignment
                                                                .topLeft,
                                                            end: Alignment
                                                                .bottomRight,
                                                          )
                                                        : null,
                                                    color: isOwnProfile
                                                        ? null
                                                        : Colors.white
                                                              .withValues(
                                                                alpha: 0.8,
                                                              ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          18,
                                                        ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.04,
                                                            ),
                                                        blurRadius: 14,
                                                        offset: const Offset(
                                                          0,
                                                          6,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: IconButton(
                                                    onPressed: isOwnProfile
                                                        ? () async {
                                                            if (!UserRestrictionService
                                                                .instance
                                                                .ensureCanUseSocialFeatures(
                                                                  context,
                                                                )) {
                                                              return;
                                                            }
                                                            await Navigator.pushNamed(
                                                              context,
                                                              "/create",
                                                            );
                                                          }
                                                        : () {
                                                            if (Navigator.of(
                                                              context,
                                                            ).canPop()) {
                                                              Navigator.of(
                                                                context,
                                                              ).pop();
                                                              return;
                                                            }
                                                            Navigator.pushReplacementNamed(
                                                              context,
                                                              "/home",
                                                            );
                                                          },
                                                    icon: Icon(
                                                      isOwnProfile
                                                          ? Icons.add_rounded
                                                          : Icons
                                                                .arrow_back_rounded,
                                                      color: isOwnProfile
                                                          ? AppColors.primary
                                                          : AppColors.textDark,
                                                      size: 24,
                                                    ),
                                                  ),
                                                ),
                                                const Spacer(),
                                                if (isOwnProfile)
                                                  ProfileTourTarget(
                                                    handle:
                                                        _profileTourSettingsTargetKey,
                                                    child: Container(
                                                      width: 48,
                                                      height: 48,
                                                      decoration: BoxDecoration(
                                                        gradient:
                                                            const LinearGradient(
                                                              colors: [
                                                                Color(
                                                                  0xFFFFE9DD,
                                                                ),
                                                                Color(
                                                                  0xFFFFF3EC,
                                                                ),
                                                              ],
                                                              begin: Alignment
                                                                  .topLeft,
                                                              end: Alignment
                                                                  .bottomRight,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              18,
                                                            ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: Colors.black
                                                                .withValues(
                                                                  alpha: 0.04,
                                                                ),
                                                            blurRadius: 14,
                                                            offset:
                                                                const Offset(
                                                                  0,
                                                                  6,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                      child: IconButton(
                                                        onPressed: () async {
                                                          await Navigator.pushNamed(
                                                            context,
                                                            "/settings",
                                                          );
                                                          if (!mounted) return;
                                                          await _refreshSettings();
                                                        },
                                                        icon: const Icon(
                                                          Icons
                                                              .settings_outlined,
                                                          color:
                                                              AppColors.primary,
                                                          size: 24,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                else
                                                  const SizedBox(width: 48),
                                              ],
                                            ),
                                          ),
                                          IgnorePointer(
                                            child: Padding(
                                              padding: EdgeInsets.only(
                                                top: topInset + 18,
                                              ),
                                              child: Text(
                                                profile.username.isNotEmpty
                                                    ? '@ ${profile.username.replaceFirst('@', '')}'
                                                    : (profile.name.isNotEmpty
                                                          ? profile.name
                                                          : 'Profile'),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.textDark,
                                                  letterSpacing: -0.4,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
          bottomNavigationBar: SocialBottomNav(
            activeTab: isOwnProfile ? SocialAppTab.profile : null,
          ),
        ),
      ),
    );
  }
}

class _ProfileErrorState extends StatelessWidget {
  const _ProfileErrorState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_search_outlined,
              size: 40,
              color: AppColors.textGrey,
            ),
            const SizedBox(height: 12),
            const Text(
              'We could not load the profile right now.',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, "/home"),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileUnavailableState extends StatelessWidget {
  const _ProfileUnavailableState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_off_outlined,
              size: 40,
              color: AppColors.textGrey,
            ),
            const SizedBox(height: 12),
            const Text(
              'This account is no longer available.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pushReplacementNamed(context, "/home"),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileBadges extends StatelessWidget {
  final String roleLabel;
  final bool isServiceProvider;
  final bool isVerifiedFallback;
  final Future<bool>? verifiedFuture;

  const _ProfileBadges({
    required this.roleLabel,
    required this.isServiceProvider,
    required this.isVerifiedFallback,
    required this.verifiedFuture,
  });

  @override
  Widget build(BuildContext context) {
    if (verifiedFuture == null) {
      return Wrap(
        spacing: 7,
        runSpacing: 5,
        children: [
          _ProfileRoleBadge(
            label: roleLabel,
            isServiceProvider: isServiceProvider,
          ),
        ],
      );
    }

    return FutureBuilder<bool>(
      future: verifiedFuture,
      builder: (context, snapshot) {
        final isVerified = isVerifiedFallback || snapshot.data == true;
        return Wrap(
          spacing: 7,
          runSpacing: 5,
          children: [
            _ProfileRoleBadge(
              label: roleLabel,
              isServiceProvider: isServiceProvider,
            ),
            if (isVerified) const _ProfileVerifiedBadge(),
          ],
        );
      },
    );
  }
}

class _ProfileRoleBadge extends StatelessWidget {
  final String label;
  final bool isServiceProvider;

  const _ProfileRoleBadge({
    required this.label,
    required this.isServiceProvider,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isServiceProvider
        ? const Color(0xFFFFF2EA)
        : const Color(0xFFFFF7ED);
    final foregroundColor = isServiceProvider
        ? AppColors.primary
        : const Color(0xFF9A3412);

    return _ProfilePill(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foregroundColor,
          fontSize: 12,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class _ProfileVerifiedBadge extends StatelessWidget {
  const _ProfileVerifiedBadge();

  @override
  Widget build(BuildContext context) {
    const foregroundColor = Color(0xFF047857);

    return Semantics(
      label: 'Verified service provider',
      child: _ProfilePill(
        backgroundColor: const Color(0xFFE9F9F0),
        foregroundColor: foregroundColor,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified_user_outlined,
              size: 15,
              color: foregroundColor,
            ),
            SizedBox(width: 4),
            Text(
              'Verified',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfilePill extends StatelessWidget {
  final Color backgroundColor;
  final Color foregroundColor;
  final Widget child;

  const _ProfilePill({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.12)),
      ),
      child: child,
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  final String label;
  final bool isPrimary;
  final VoidCallback? onPressed;

  const _ProfileActionButton({
    required this.label,
    required this.isPrimary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    const radius = 18.0;

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppColors.primary, width: 1.8),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(radius),
            splashColor: AppColors.primary.withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 46),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Center(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  final String imageUrl;
  final String fallbackInitials;
  final double size;

  const _ProfileAvatar({
    required this.imageUrl,
    required this.fallbackInitials,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    Widget fallback() {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradientDiagonal,
          borderRadius: BorderRadius.circular(30),
        ),
        alignment: Alignment.center,
        child: Text(
          fallbackInitials,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      );
    }

    if (imageUrl.isEmpty) {
      return fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback(),
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _ProfileStat({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );

    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: content,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: content,
        ),
      ),
    );
  }
}
