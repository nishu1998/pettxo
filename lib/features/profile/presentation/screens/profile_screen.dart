import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../messages/data/repositories/chat_repository.dart';
import '../../../messages/presentation/screens/chat_detail_screen.dart';
import '../../../profile/data/repositories/profile_content_repository.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/profile_service_listing.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../profile/presentation/widgets/profile_content_sections.dart';
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

class _ProfileScreenState extends State<ProfileScreen> {
  static final Map<String, ProfileFollowCounts> _sharedFollowCountCache =
      <String, ProfileFollowCounts>{};

  final ProfileRepository _profileRepository = ProfileRepository();
  final ProfileContentRepository _contentRepository =
      ProfileContentRepository();
  final ServicesRepository _servicesRepository = ServicesRepository();
  final SettingsService _settingsService = SettingsService();
  final FollowRepository _followRepository = FollowRepository();
  final ChatRepository _chatRepository = ChatRepository();
  late Future<AppSettings> _settingsFuture;
  int _selectedSectionIndex = 0;
  bool _showProfileSpotlight = false;
  String _followTargetUserId = '';
  Future<bool>? _followStateFuture;
  bool? _followStateOverride;
  bool _isFollowActionRunning = false;
  bool _isOpeningDirectChat = false;
  final Map<String, Future<ProfileFollowCounts>> _followCountRequests =
      <String, Future<ProfileFollowCounts>>{};

  @override
  void initState() {
    super.initState();
    _settingsFuture = _loadInitialSettings();
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

  void _ensureFollowCountsLoaded(String userId, {bool forceRefresh = false}) {
    final trimmedUserId = userId.trim();
    if (trimmedUserId.isEmpty) return;

    if (forceRefresh) {
      _followCountRequests.remove(trimmedUserId);
    } else if (_sharedFollowCountCache.containsKey(trimmedUserId) ||
        _followCountRequests.containsKey(trimmedUserId)) {
      return;
    }

    _requestFollowCounts(trimmedUserId)
        .then((counts) {
          _followCountRequests.remove(trimmedUserId);
          final previous = _sharedFollowCountCache[trimmedUserId];
          final didChange =
              previous?.followerCount != counts.followerCount ||
              previous?.followingCount != counts.followingCount;
          _sharedFollowCountCache[trimmedUserId] = counts;
          if (!mounted || !didChange) return;
          setState(() {});
        })
        .catchError((_) {
          _followCountRequests.remove(trimmedUserId);
          // Keep the last visible counts if refresh fails.
        });
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

  Future<void> _openManageServicesSheet(
    BuildContext context,
    List<ProfileServiceListing> services,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Manage services',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pause bookings temporarily or remove services you no longer offer.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                ...services.map((service) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ManageServiceTile(
                      service: service,
                      onPause: () async {
                        await _servicesRepository.setServicePaused(
                          service.id,
                          !service.isPaused,
                        );
                        if (!mounted ||
                            !context.mounted ||
                            !sheetContext.mounted) {
                          return;
                        }
                        Navigator.pop(sheetContext);
                        setState(() {});
                        AppFeedback.show(
                          context,
                          message: service.isPaused
                              ? 'Service resumed.'
                              : 'Service paused.',
                          tone: AppFeedbackTone.success,
                        );
                      },
                      onDelete: () async {
                        await _servicesRepository.deleteService(service.id);
                        if (!mounted ||
                            !context.mounted ||
                            !sheetContext.mounted) {
                          return;
                        }
                        Navigator.pop(sheetContext);
                        setState(() {});
                        AppFeedback.show(
                          context,
                          message: 'Service removed from your profile.',
                          tone: AppFeedbackTone.success,
                        );
                      },
                    ),
                  );
                }),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: SecondaryButton(
                    label: 'Pause all services',
                    icon: Icons.pause_circle_outline_rounded,
                    onPressed: () async {
                      for (final service in services) {
                        await _servicesRepository.setServicePaused(
                          service.id,
                          true,
                        );
                      }
                      if (!mounted ||
                          !context.mounted ||
                          !sheetContext.mounted) {
                        return;
                      }
                      Navigator.pop(sheetContext);
                      setState(() {});
                      AppFeedback.show(
                        context,
                        message: 'All services are paused.',
                        tone: AppFeedbackTone.success,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    final currentUserId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    final requestedUserId = widget.userId?.trim() ?? '';
    final isOwnProfile =
        requestedUserId.isEmpty || requestedUserId == currentUserId;
    final topInset = MediaQuery.paddingOf(context).top;
    const topBarHeight = 74.0;
    final topContentPadding = topInset + topBarHeight;
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);

    return SocialTabBackScope(
      activeTab: SocialAppTab.profile,
      enabled: isOwnProfile,
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
                _syncFollowState(
                  currentUserId: currentUserId,
                  profileUserId: profile.uid,
                  isOwnProfile: isOwnProfile,
                );
                _ensureFollowCountsLoaded(profile.uid);
                final cachedCounts = _sharedFollowCountCache[profile.uid];

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
                    final selectedSectionIndex = _selectedSectionIndex;

                    return StreamBuilder<List<SocialPostModel>>(
                      stream: _contentRepository.watchPostsForProfile(profile),
                      builder: (context, postsSnapshot) {
                        final posts =
                            postsSnapshot.data ?? const <SocialPostModel>[];

                        return Stack(
                          children: [
                            // The profile list fills the screen first so cards can
                            // move behind the glass header and bottom nav overlays.
                            ListView(
                              padding: EdgeInsets.fromLTRB(
                                18,
                                topContentPadding,
                                18,
                                bottomContentPadding,
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
                                    borderRadius: BorderRadius.circular(28),
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
                                            imageUrl: profile.profileImageUrl,
                                            fallbackInitials: profile.initials,
                                            size: 96,
                                          ),
                                          const SizedBox(width: 18),
                                          Expanded(
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                top: 2,
                                              ),
                                              child: _buildProfileStatsRow(
                                                context: context,
                                                postsCount: posts.length,
                                                followerCount:
                                                    cachedCounts
                                                        ?.followerCount ??
                                                    profile.followerCount,
                                                followingCount:
                                                    cachedCounts
                                                        ?.followingCount ??
                                                    profile.followingCount,
                                                isOwnProfile: isOwnProfile,
                                                profileUserId: profile.uid,
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
                                      Row(
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: const BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              profile.roleLabel,
                                              style: const TextStyle(
                                                color: AppColors.textGrey,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (profile.isServiceProvider) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          profile.providerReviewSummary,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: profile.hasReviews
                                                ? const Color(0xFF9A3412)
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
                                            size: 22,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              profile.location.isEmpty
                                                  ? 'Add your location in profile settings'
                                                  : profile.location,
                                              style: const TextStyle(
                                                color: AppColors.textGrey,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
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
                                                    label: 'Edit profile',
                                                    isPrimary: false,
                                                    onPressed: () async {
                                                      await Navigator.pushNamed(
                                                        context,
                                                        "/settings/profile",
                                                      );
                                                    },
                                                  )
                                                : FutureBuilder<bool>(
                                                    future: _followStateFuture,
                                                    builder: (context, followSnapshot) {
                                                      final isFollowing =
                                                          _followStateOverride ??
                                                          followSnapshot.data ??
                                                          false;
                                                      return SecondaryButton(
                                                        label:
                                                            _isFollowActionRunning
                                                            ? 'Updating...'
                                                            : (isFollowing
                                                                  ? 'Following'
                                                                  : 'Follow'),
                                                        size: AppButtonSize
                                                            .compact,
                                                        onPressed:
                                                            currentUserId
                                                                    .isEmpty ||
                                                                followSnapshot
                                                                        .connectionState ==
                                                                    ConnectionState
                                                                        .waiting
                                                            ? null
                                                            : () => _toggleFollow(
                                                                currentUserId:
                                                                    currentUserId,
                                                                profile:
                                                                    profile,
                                                                currentlyFollowing:
                                                                    isFollowing,
                                                              ),
                                                      );
                                                    },
                                                  ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: isOwnProfile
                                                ? _ProfileActionButton(
                                                    label: 'Bookings',
                                                    isPrimary: true,
                                                    onPressed: () {
                                                      Navigator.pushNamed(
                                                        context,
                                                        "/bookings",
                                                      );
                                                    },
                                                  )
                                                : SecondaryButton(
                                                    label: _isOpeningDirectChat
                                                        ? "Opening..."
                                                        : "Message",
                                                    size: AppButtonSize.compact,
                                                    onPressed:
                                                        currentUserId.isEmpty
                                                        ? null
                                                        : () => _openDirectChat(
                                                            profile: profile,
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
                                if (isOwnProfile && _showProfileSpotlight) ...[
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
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                    ),
                                    child: const Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                "Profile spotlight",
                                                style: TextStyle(
                                                  color: AppColors.primary,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              SizedBox(height: 6),
                                              Text(
                                                "Showcase both personality and services so followers can trust you before they book.",
                                                style: TextStyle(
                                                  color: AppColors.textDark,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.45,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Icon(
                                          Icons.workspace_premium_outlined,
                                          color: AppColors.primary,
                                          size: 28,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 6),
                                ProfileSectionTabs(
                                  selectedIndex: selectedSectionIndex,
                                  showServices: true,
                                  serviceCount: services.length,
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
                                    onAdd: () async {
                                      if (!UserRestrictionService.instance
                                          .ensureCanUseBookingFeatures(
                                            context,
                                          )) {
                                        return;
                                      }
                                      final added = await Navigator.pushNamed(
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
                                    onManage: () => _openManageServicesSheet(
                                      context,
                                      services,
                                    ),
                                  ),
                              ],
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
                                    color: Colors.white.withValues(alpha: 0.5),
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
                                                      begin: Alignment.topLeft,
                                                      end:
                                                          Alignment.bottomRight,
                                                    )
                                                  : null,
                                              color: isOwnProfile
                                                  ? null
                                                  : Colors.white.withValues(
                                                      alpha: 0.8,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.04),
                                                  blurRadius: 14,
                                                  offset: const Offset(0, 6),
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
                                                    : Icons.arrow_back_rounded,
                                                color: isOwnProfile
                                                    ? AppColors.primary
                                                    : AppColors.textDark,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          if (isOwnProfile)
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [
                                                    Color(0xFFFFE9DD),
                                                    Color(0xFFFFF3EC),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(18),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.04,
                                                        ),
                                                    blurRadius: 14,
                                                    offset: const Offset(0, 6),
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
                                                  Icons.settings_outlined,
                                                  color: AppColors.primary,
                                                  size: 24,
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
        ),
        bottomNavigationBar: const SocialBottomNav(
          activeTab: SocialAppTab.profile,
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
    final radius = AppButtonTokens.radius(AppButtonSize.compact);
    final disabled = onPressed == null;
    const secondaryButtonColor = Colors.white;

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isPrimary ? AppColors.brandGradient : null,
          color: isPrimary ? null : secondaryButtonColor,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(radius),
            splashColor: isPrimary
                ? Colors.white.withValues(alpha: 0.12)
                : AppColors.textDark.withValues(alpha: 0.05),
            highlightColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: AppButtonTokens.height(AppButtonSize.compact),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: AppButtonTokens.horizontalPadding(
                    AppButtonSize.compact,
                  ),
                  vertical: AppButtonTokens.verticalPadding(
                    AppButtonSize.compact,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isPrimary ? Colors.white : AppColors.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
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
