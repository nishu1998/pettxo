import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../profile/data/repositories/profile_content_repository.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/profile_service_listing.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../profile/presentation/widgets/profile_content_sections.dart';
import '../../../settings/data/services/settings_service.dart';
import '../../../settings/domain/models/app_settings.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileRepository _profileRepository = ProfileRepository();
  final ProfileContentRepository _contentRepository =
      const ProfileContentRepository();
  final SettingsService _settingsService = SettingsService();
  late Future<AppSettings> _settingsFuture;
  int _selectedSectionIndex = 0;

  @override
  void initState() {
    super.initState();
    _settingsFuture = _settingsService.loadSettings();
  }

  Future<void> _refreshSettings() async {
    setState(() {
      _settingsFuture = _settingsService.loadSettings();
    });
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
                        await _contentRepository.setServicePaused(
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
                        await _contentRepository.deleteService(service.id);
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
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await _contentRepository.pauseAllServices();
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
                    icon: const Icon(Icons.pause_circle_outline_rounded),
                    label: const Text('Pause all services'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textDark,
                      minimumSize: const Size.fromHeight(50),
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.16),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        child: FutureBuilder<AppSettings>(
          future: _settingsFuture,
          builder: (context, settingsSnapshot) {
            if (!settingsSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final settings = settingsSnapshot.data!;

            return StreamBuilder<UserProfile>(
              stream: _profileRepository.watchCurrentUserProfile(),
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (profileSnapshot.hasError || !profileSnapshot.hasData) {
                  return const _ProfileErrorState();
                }

                final profile = profileSnapshot.data!;
                final posts = _contentRepository.getPostsForProfile(profile);

                return FutureBuilder<List<ProfileServiceListing>>(
                  future: _contentRepository.getServicesForProfile(
                    profile,
                    hasListedServices: settings.hasListedServices,
                  ),
                  builder: (context, servicesSnapshot) {
                    final services = servicesSnapshot.data ?? const [];
                    final selectedSectionIndex = services.isEmpty
                        ? 0
                        : _selectedSectionIndex;

                    return Stack(
                      children: [
                        Positioned(
                          top: -50,
                          right: -30,
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withValues(alpha: 0.07),
                            ),
                          ),
                        ),
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                14,
                                18,
                                10,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(28),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.08,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: AppColors.background,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: IconButton(
                                        onPressed: () =>
                                            Navigator.pushReplacementNamed(
                                              context,
                                              "/home",
                                            ),
                                        icon: const Icon(
                                          Icons.arrow_back_rounded,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Profile",
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.textDark,
                                            ),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            "Your presence, services and pet stories",
                                            style: TextStyle(
                                              color: AppColors.textGrey,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: AppColors.background,
                                        borderRadius: BorderRadius.circular(14),
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
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  0,
                                  18,
                                  120,
                                ),
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(22),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(
                                        alpha: 0.97,
                                      ),
                                      borderRadius: BorderRadius.circular(30),
                                      border: Border.all(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.08,
                                        ),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.04,
                                          ),
                                          blurRadius: 22,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _ProfileAvatar(
                                              imageUrl: profile.profileImageUrl,
                                              fallbackInitials:
                                                  profile.initials,
                                              size: 92,
                                            ),
                                            const SizedBox(width: 18),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Wrap(
                                                    spacing: 10,
                                                    runSpacing: 8,
                                                    crossAxisAlignment:
                                                        WrapCrossAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        profile.name.isEmpty
                                                            ? 'Your Name'
                                                            : profile.name,
                                                        style: const TextStyle(
                                                          fontSize: 24,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: AppColors
                                                              .textDark,
                                                        ),
                                                      ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 12,
                                                              vertical: 6,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: const Color(
                                                            0xFFFFF2EA,
                                                          ),
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                999,
                                                              ),
                                                        ),
                                                        child: Text(
                                                          profile.roleLabel,
                                                          style:
                                                              const TextStyle(
                                                                color: AppColors
                                                                    .primary,
                                                                fontSize: 12,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    profile
                                                            .displayUsername
                                                            .isEmpty
                                                        ? '@username'
                                                        : profile
                                                              .displayUsername,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: AppColors.textGrey,
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            profile.bio.isEmpty
                                                ? 'Tell people a little about you from Settings > Profile details.'
                                                : profile.bio,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: profile.bio.isEmpty
                                                  ? AppColors.textGrey
                                                  : AppColors.textDark,
                                              height: 1.45,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.location_on_outlined,
                                              color: AppColors.textGrey,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
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
                                        const SizedBox(height: 22),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _ProfileStat(
                                                label: "posts",
                                                value: "${posts.length}",
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: _ProfileStat(
                                                label: "followers",
                                                value: "1234",
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Expanded(
                                              child: _ProfileStat(
                                                label: "services",
                                                value: "${services.length}",
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
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
                                  const SizedBox(height: 18),
                                  ProfileSectionTabs(
                                    selectedIndex: selectedSectionIndex,
                                    showServices: services.isNotEmpty,
                                    onChanged: (index) {
                                      setState(() {
                                        _selectedSectionIndex = index;
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 18),
                                  if (selectedSectionIndex == 0)
                                    ProfilePostsSection(posts: posts)
                                  else
                                    ProfileServicesSection(
                                      services: services,
                                      canManage:
                                          profile.isServiceProvider &&
                                          settings.showManageServicesOnProfile,
                                      onAdd: () async {
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
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
      bottomNavigationBar: const SocialBottomNav(
        activeTab: SocialAppTab.profile,
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

  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
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
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
