import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/utils/service_ranking.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../data/repositories/services_repository.dart';
import '../../domain/models/service_model.dart';
import '../../../profile/presentation/screens/service_detail_screen.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  final ServicesRepository _servicesRepository = ServicesRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'All Services';
  String _searchQuery = '';
  _DiscoveryRadiusFilter _selectedRadius = _DiscoveryRadiusFilter.smart;
  double? _userLatitude;
  double? _userLongitude;
  UserProfile? _currentUserProfile;

  static const _categories = [
    'All Services',
    'Grooming',
    'Sitting',
    'Boarding',
    'Walking',
    'Vet Visit',
  ];

  Stream<List<ServiceModel>> get _servicesStream {
    if (_selectedCategory == 'All Services') {
      return _servicesRepository.watchActiveServices();
    }

    return _servicesRepository.watchActiveServicesByCategory(_selectedCategory);
  }

  @override
  void initState() {
    super.initState();
    _primeUserLocation();
    _primeCurrentUserProfile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _primeUserLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _userLatitude = position.latitude;
        _userLongitude = position.longitude;
      });
      if (kDebugMode) {
        debugPrint(
          'Services discovery debug -> user location available: true (${position.latitude}, ${position.longitude})',
        );
      }
    } catch (_) {
      // Discovery can still rank organically without location, so failures are
      // intentionally non-blocking here.
      if (kDebugMode) {
        debugPrint(
          'Services discovery debug -> user location available: false',
        );
      }
    }
  }

  Future<void> _primeCurrentUserProfile() async {
    try {
      final profile = await _profileRepository.getCurrentUserProfile();
      if (!mounted) return;
      setState(() => _currentUserProfile = profile);
    } catch (_) {
      // Discovery can still work without profile fallback details.
    }
  }

  void _showFiltersSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        var draftRadius = _selectedRadius;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Filters',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Radius',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ..._DiscoveryRadiusFilter.values.map((option) {
                        final isSelected = draftRadius == option;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              setSheetState(() => draftRadius = option);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFFFFF1EA)
                                    : const Color(0xFFFFFCFA),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary.withValues(alpha: 0.28)
                                      : AppColors.primary.withValues(alpha: 0.08),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      option.label,
                                      style: TextStyle(
                                        color: AppColors.textDark,
                                        fontSize: 14.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w800
                                            : FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    isSelected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textGrey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: SecondaryButton(
                              label: 'Clear Filters',
                              onPressed: () {
                                setState(() {
                                  _selectedRadius = _DiscoveryRadiusFilter.smart;
                                });
                                Navigator.pop(context);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GradientButton(
                              label: 'Apply',
                              onPressed: () {
                                setState(() {
                                  _selectedRadius = draftRadius;
                                });
                                Navigator.pop(context);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  _DiscoveryPresentation _buildDiscoveryPresentation(List<ServiceModel> services) {
    final userLatitude = _userLatitude;
    final userLongitude = _userLongitude;
    final hasUserLocation = userLatitude != null && userLongitude != null;
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final normalizedCity = _currentUserProfile?.city.trim().toLowerCase() ?? '';
    final normalizedState = _currentUserProfile?.state.trim().toLowerCase() ?? '';

    final searchedServices = normalizedQuery.isEmpty
        ? services
        : services
              .where((service) => _matchesSearch(service, normalizedQuery))
              .toList(growable: false);

    // Discovery ranking is intentionally client-side for now so we can tune
    // the formula without changing Firestore writes. This can move to a server
    // ranking pipeline later (for example Cloud Functions, Algolia, or a
    // dedicated search index) once discovery scale and analytics require it.
    final ranked = searchedServices.map((service) {
      final distanceKm = hasUserLocation && _hasCoordinates(service)
          ? Geolocator.distanceBetween(
                  userLatitude,
                  userLongitude,
                  service.latitude,
                  service.longitude,
                ) /
                1000
          : null;

      final breakdown = ServiceRanking.calculate(
        ServiceRankingInput(
          ratingAverage: service.ratingAverage,
          ratingCount: service.ratingCount,
          completedBookingCount: service.completedBookingCount,
          // When location is missing we feed a neutral distance so relative
          // ordering still comes from rating, completions, freshness, and
          // active sponsor/admin boosts instead of distance.
          distanceKm: distanceKm ?? 15,
          updatedAt: service.updatedAt,
          publishedAt: service.publishedAt,
          isActive: service.isActive && !service.isDeleted && !service.isPaused,
          activeSponsorBoost: service.activeSponsorBoost,
          activeAdminRankBoost: service.activeAdminRankBoost,
        ),
      );

      if (kDebugMode) {
        debugPrint(
          'Services discovery ranking -> ${service.id} | ${service.title} | '
          'locationAvailable=$hasUserLocation | '
          'distanceKm=${distanceKm?.toStringAsFixed(2) ?? 'n/a'} | '
          'rating=${breakdown.ratingScore.toStringAsFixed(2)} | '
          'distance=${breakdown.distanceScore.toStringAsFixed(2)} | '
          'completed=${breakdown.completedBookingScore.toStringAsFixed(2)} | '
          'freshness=${breakdown.freshnessScore.toStringAsFixed(2)} | '
          'trustBadge=${breakdown.trustBadgeScore.toStringAsFixed(2)} | '
          'organic=${breakdown.organicScore.toStringAsFixed(2)} | '
          'sponsorBoost=${service.activeSponsorBoost.toStringAsFixed(2)} | '
          'adminBoost=${service.activeAdminRankBoost.toStringAsFixed(2)} | '
          'final=${breakdown.finalRankingScore.toStringAsFixed(2)}',
        );
      }

      return _RankedService(
        service: service,
        distanceKm: distanceKm,
        finalScore: breakdown.finalRankingScore,
        isCityStatePriority:
            !hasUserLocation &&
            _matchesCityState(
              service: service,
              normalizedCity: normalizedCity,
              normalizedState: normalizedState,
            ),
      );
    }).toList();

    ranked.sort((a, b) {
      if (!hasUserLocation) {
        final cityPriority = (b.isCityStatePriority ? 1 : 0).compareTo(
          a.isCityStatePriority ? 1 : 0,
        );
        if (cityPriority != 0) return cityPriority;
      }
      return b.finalScore.compareTo(a.finalScore);
    });

    List<_RankedService> primaryServices = ranked;
    List<_RankedService> secondaryServices = const [];
    String? helperMessage;
    String? secondaryTitle;

    final selectedRadiusKm = _selectedRadius.radiusKm;
    if (selectedRadiusKm != null && hasUserLocation) {
      final insideRadius = ranked
          .where(
            (entry) => entry.distanceKm != null && entry.distanceKm! <= selectedRadiusKm,
          )
          .toList(growable: false);
      final outsideRadius = ranked
          .where(
            (entry) => entry.distanceKm == null || entry.distanceKm! > selectedRadiusKm,
          )
          .toList(growable: false);

      primaryServices = insideRadius;
      secondaryServices = outsideRadius;
      secondaryTitle = outsideRadius.isEmpty
          ? null
          : 'More services outside your selected area';

      if (insideRadius.isEmpty && outsideRadius.isNotEmpty) {
        helperMessage =
            'No nearby services found within ${selectedRadiusKm.toStringAsFixed(0)} km. Showing more services around your city.';
      }
    } else if (!hasUserLocation) {
      helperMessage = 'Enable location for better nearby results.';
    }

    if (kDebugMode) {
      debugPrint(
        'Services discovery debug -> selected radius mode: ${_selectedRadius.label}',
      );
      debugPrint(
        'Services discovery debug -> search query: ${normalizedQuery.isEmpty ? '(empty)' : normalizedQuery}',
      );
      debugPrint(
        'Services discovery debug -> services inside radius count: ${primaryServices.length}',
      );
      debugPrint(
        'Services discovery debug -> outside radius count: ${secondaryServices.length}',
      );
      debugPrint(
        'Services discovery debug -> final visible service count: ${primaryServices.length + secondaryServices.length}',
      );
    }

    return _DiscoveryPresentation(
      allMatchedCount: searchedServices.length,
      primaryServices: primaryServices,
      secondaryServices: secondaryServices,
      helperMessage: helperMessage,
      secondaryTitle: secondaryTitle,
      hasUserLocation: hasUserLocation,
      selectedRadius: _selectedRadius,
      searchQuery: _searchQuery.trim(),
    );
  }

  bool _hasCoordinates(ServiceModel service) {
    return service.latitude != 0 || service.longitude != 0;
  }

  bool _matchesSearch(ServiceModel service, String normalizedQuery) {
    final haystack = <String>[
      service.title,
      service.description,
      service.category,
      service.ownerName,
      service.ownerUsername,
    ].map((value) => value.trim().toLowerCase()).join(' ');
    return haystack.contains(normalizedQuery);
  }

  bool _matchesCityState({
    required ServiceModel service,
    required String normalizedCity,
    required String normalizedState,
  }) {
    final serviceCity = service.city.trim().toLowerCase();
    final serviceState = service.state.trim().toLowerCase();
    final cityMatches = normalizedCity.isNotEmpty && serviceCity == normalizedCity;
    final stateMatches =
        normalizedState.isNotEmpty && serviceState == normalizedState;
    return cityMatches || stateMatches;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    const topBarHeight = 84.0;
    final topContentPadding = topInset + topBarHeight + 26;
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          // The scroll view fills the whole screen so cards can move under the
          // glass overlays. Internal padding preserves access to the first and
          // last interactive elements.
          StreamBuilder<List<ServiceModel>>(
            stream: _servicesStream,
            builder: (context, snapshot) {
              final services = snapshot.data ?? const <ServiceModel>[];
              final discoveryPresentation = _buildDiscoveryPresentation(services);
              if (kDebugMode) {
                debugPrint(
                  'Services discovery debug -> loaded service count: ${services.length}',
                );
                debugPrint(
                  'Services discovery debug -> user location available: ${_userLatitude != null && _userLongitude != null}',
                );
              }

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  18,
                  topContentPadding,
                  18,
                  bottomContentPadding,
                ),
                children: [
                  _ServiceSearchAndFilters(
                    searchController: _searchController,
                    onSearchChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                    selectedCategory: _selectedCategory,
                    categories: _categories,
                    onCategorySelected: (category) {
                      setState(() => _selectedCategory = category);
                    },
                  ),
                  const SizedBox(height: 18),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (snapshot.hasError)
                    const _ServicesEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Unable to load services',
                      message:
                          'Please check your connection and try again in a moment.',
                    )
                  else if (services.isEmpty)
                    const _ServicesEmptyState(
                      icon: Icons.design_services_outlined,
                      title: 'No services yet',
                      message:
                          'Services will appear here after people publish listings in your marketplace.',
                    )
                  else if (discoveryPresentation.allMatchedCount == 0)
                    _ServicesEmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No services found',
                      message:
                          "No services found for '${discoveryPresentation.searchQuery}'.",
                    )
                  else if (discoveryPresentation.primaryServices.isEmpty &&
                      discoveryPresentation.secondaryServices.isEmpty)
                    const _ServicesEmptyState(
                      icon: Icons.design_services_outlined,
                      title: 'No services yet',
                      message:
                          'Services will appear here after people publish listings in your marketplace.',
                    )
                  else
                    ...[
                      if (discoveryPresentation.helperMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _DiscoveryInfoBanner(
                            message: discoveryPresentation.helperMessage!,
                          ),
                        ),
                      ...discoveryPresentation.primaryServices.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _MarketplaceServiceCard(service: entry.service),
                        );
                      }),
                      if (discoveryPresentation.secondaryServices.isNotEmpty) ...[
                        if (discoveryPresentation.secondaryTitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 14),
                            child: Text(
                              discoveryPresentation.secondaryTitle!,
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ...discoveryPresentation.secondaryServices.map((entry) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _MarketplaceServiceCard(service: entry.service),
                          );
                        }),
                      ],
                    ],
                ],
              );
            },
          ),
          Positioned(
            left: 18,
            right: 18,
            top: topInset + 14,
            child: GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              borderRadius: BorderRadius.circular(28),
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              blurSigma: 20,
              border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.56),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      onPressed: () =>
                          Navigator.pushReplacementNamed(context, "/home"),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Services",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.56),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      onPressed: _showFiltersSheet,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SocialBottomNav(
        activeTab: SocialAppTab.services,
      ),
    );
  }
}

class _RankedService {
  final ServiceModel service;
  final double? distanceKm;
  final double finalScore;
  final bool isCityStatePriority;

  const _RankedService({
    required this.service,
    required this.distanceKm,
    required this.finalScore,
    this.isCityStatePriority = false,
  });
}

enum _DiscoveryRadiusFilter {
  smart('Nearby first / Smart discovery', null),
  km5('5 km', 5),
  km10('10 km', 10),
  km25('25 km', 25),
  km50('50 km', 50);

  const _DiscoveryRadiusFilter(this.label, this.radiusKm);

  final String label;
  final double? radiusKm;
}

class _DiscoveryPresentation {
  final int allMatchedCount;
  final List<_RankedService> primaryServices;
  final List<_RankedService> secondaryServices;
  final String? helperMessage;
  final String? secondaryTitle;
  final bool hasUserLocation;
  final _DiscoveryRadiusFilter selectedRadius;
  final String searchQuery;

  const _DiscoveryPresentation({
    required this.allMatchedCount,
    required this.primaryServices,
    required this.secondaryServices,
    required this.helperMessage,
    required this.secondaryTitle,
    required this.hasUserLocation,
    required this.selectedRadius,
    required this.searchQuery,
  });
}

class _ServiceSearchAndFilters extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String selectedCategory;
  final List<String> categories;
  final ValueChanged<String> onCategorySelected;

  const _ServiceSearchAndFilters({
    required this.searchController,
    required this.onSearchChanged,
    required this.selectedCategory,
    required this.categories,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCFA),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppColors.textGrey),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    onChanged: onSearchChanged,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Search services, sitters or nearby care...',
                      hintStyle: TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 46,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final category = categories[index];
                return _CategoryChip(
                  label: category,
                  isActive: selectedCategory == category,
                  onTap: () => onCategorySelected(category),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DiscoveryInfoBanner extends StatelessWidget {
  final String message;

  const _DiscoveryInfoBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4EC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          gradient: isActive ? AppColors.brandGradient : null,
          color: isActive ? null : const Color(0xFFFFF4E8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.textDark,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _MarketplaceServiceCard extends StatelessWidget {
  final ServiceModel service;

  const _MarketplaceServiceCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ServiceDetailScreen(service: service.toProfileListing()),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(26),
                ),
                child: SizedBox(
                  width: 132,
                  height: 152,
                  child: service.primaryPhotoUrl.isEmpty
                      ? const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradientDiagonal,
                          ),
                          child: Center(
                            child: Icon(
                              Icons.pets_rounded,
                              color: Colors.white,
                              size: 42,
                            ),
                          ),
                        )
                      : Image.network(
                          service.primaryPhotoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradientDiagonal,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.pets_rounded,
                                color: Colors.white,
                                size: 42,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Provided by ${_providerLabel(service)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (service.isSponsorActive) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF2EA),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Sponsored',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        service.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          height: 1.35,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        service.ratingCount > 0
                            ? '⭐ ${service.ratingAverage.toStringAsFixed(1)} · ${service.ratingCount} ${service.ratingCount == 1 ? 'review' : 'reviews'}'
                            : 'No reviews yet',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: service.ratingCount > 0
                              ? const Color(0xFF9A3412)
                              : AppColors.textGrey,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.pets_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${service.animalType} · ${service.category}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: AppColors.textGrey,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              service.displayAddress.isEmpty
                                  ? 'Location shared after booking'
                                  : service.displayAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          Text(
                            '₹${service.pricePerSession}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _providerLabel(ServiceModel service) {
    final ownerName = service.ownerName.trim();
    if (ownerName.isNotEmpty) return ownerName;
    final ownerUsername = service.ownerUsername.trim().replaceFirst('@', '');
    if (ownerUsername.isNotEmpty) return ownerUsername;
    return 'Service provider';
  }
}

class _ServicesEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _ServicesEmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
