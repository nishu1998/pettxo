import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/services/network_status_service.dart';
import '../../../../core/utils/service_ranking.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/live_user_identity_resolver.dart';
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
  final ScrollController _scrollController = ScrollController();
  late Stream<List<ServiceModel>> _activeServicesStream;
  String _selectedAnimal = 'All';
  String _selectedCategory = 'All';
  String _searchQuery = '';
  _DiscoveryRadiusFilter _selectedRadius = _DiscoveryRadiusFilter.smart;
  double? _userLatitude;
  double? _userLongitude;
  UserProfile? _currentUserProfile;
  bool _isTopBarVisible = true;
  double _lastScrollOffset = 0;
  double _scrollDeltaAccumulator = 0;

  static const double _topBarHideThreshold = 18;
  static const double _topBarShowThreshold = 12;
  static const double _topBarTopResetOffset = 8;

  static const _animals = [
    'All',
    'Dog',
    'Cat',
    'Bird',
    'Rabbit',
    'Fish',
    'Guinea Pig',
    'Hamster',
    'Turtle / Tortoise',
    'Lizard / Reptile',
    'Other',
  ];

  static const _categories = [
    'All',
    'Walking',
    'Grooming',
    'Training',
    'Boarding',
    'Sitting',
    'Vet Visit',
    'Nail Trimming',
    'Bath & Brush',
    'Wing Clipping',
    'Tank Cleaning',
    'Feeding Care',
    'General Care',
    'Other',
  ];

  Stream<List<ServiceModel>> _buildServicesStream() {
    return _servicesRepository.watchActiveServicesFiltered(
      category: _selectedCategory == 'All' ? null : _selectedCategory,
    );
  }

  void _refreshServicesStream() {
    _activeServicesStream = _buildServicesStream();
  }

  @override
  void initState() {
    super.initState();
    _refreshServicesStream();
    _scrollController.addListener(_handleScroll);
    _primeUserLocation();
    _primeCurrentUserProfile();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final direction = position.userScrollDirection;
    final pixels = position.pixels;
    final delta = pixels - _lastScrollOffset;
    _lastScrollOffset = pixels;

    if (pixels <= _topBarTopResetOffset) {
      _scrollDeltaAccumulator = 0;
      if (!_isTopBarVisible && mounted) {
        setState(() => _isTopBarVisible = true);
      }
    } else if (direction == ScrollDirection.reverse && delta > 0) {
      _scrollDeltaAccumulator = (_scrollDeltaAccumulator + delta).clamp(
        0.0,
        _topBarHideThreshold,
      );
      if (_isTopBarVisible &&
          _scrollDeltaAccumulator >= _topBarHideThreshold &&
          mounted) {
        _scrollDeltaAccumulator = 0;
        setState(() => _isTopBarVisible = false);
      }
    } else if (direction == ScrollDirection.forward && delta < 0) {
      _scrollDeltaAccumulator = (_scrollDeltaAccumulator + delta).clamp(
        -_topBarShowThreshold,
        0.0,
      );
      if (!_isTopBarVisible &&
          _scrollDeltaAccumulator <= -_topBarShowThreshold &&
          mounted) {
        _scrollDeltaAccumulator = 0;
        setState(() => _isTopBarVisible = true);
      }
    } else if (direction == ScrollDirection.idle) {
      _scrollDeltaAccumulator = 0;
    }
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
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        var draftRadius = _selectedRadius;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final mediaQuery = MediaQuery.of(context);
            final maxSheetHeight = mediaQuery.size.height * 0.82;
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxSheetHeight),
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
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: _DiscoveryRadiusFilter.values
                                  .map((option) {
                                    final isSelected = draftRadius == option;
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(18),
                                        onTap: () {
                                          setSheetState(
                                            () => draftRadius = option,
                                          );
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
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                            border: Border.all(
                                              color: isSelected
                                                  ? AppColors.primary
                                                        .withValues(alpha: 0.28)
                                                  : AppColors.primary
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
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
                                                    ? Icons
                                                          .radio_button_checked_rounded
                                                    : Icons
                                                          .radio_button_off_rounded,
                                                color: isSelected
                                                    ? AppColors.primary
                                                    : AppColors.textGrey,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: SecondaryButton(
                                label: 'Clear Filters',
                                onPressed: () {
                                  setState(() {
                                    _selectedRadius =
                                        _DiscoveryRadiusFilter.smart;
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
              ),
            );
          },
        );
      },
    );
  }

  _DiscoveryPresentation _buildDiscoveryPresentation(
    List<ServiceModel> services,
  ) {
    final userLatitude = _userLatitude;
    final userLongitude = _userLongitude;
    final hasUserLocation = userLatitude != null && userLongitude != null;
    final normalizedQuery = _searchQuery.trim().toLowerCase();
    final normalizedCity = _currentUserProfile?.city.trim().toLowerCase() ?? '';
    final normalizedState =
        _currentUserProfile?.state.trim().toLowerCase() ?? '';

    final normalizedAnimal = _selectedAnimal.trim().toLowerCase();
    final animalFilteredServices = normalizedAnimal == 'all'
        ? services
        : services
              .where(
                (service) =>
                    service.animalType.trim().toLowerCase() == normalizedAnimal,
              )
              .toList(growable: false);

    final searchedServices = normalizedQuery.isEmpty
        ? animalFilteredServices
        : services
              .where((service) => _matchesSearch(service, normalizedQuery))
              .where(
                (service) =>
                    normalizedAnimal == 'all' ||
                    service.animalType.trim().toLowerCase() == normalizedAnimal,
              )
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
            (entry) =>
                entry.distanceKm != null &&
                entry.distanceKm! <= selectedRadiusKm,
          )
          .toList(growable: false);
      final outsideRadius = ranked
          .where(
            (entry) =>
                entry.distanceKm == null ||
                entry.distanceKm! > selectedRadiusKm,
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
    final cityMatches =
        normalizedCity.isNotEmpty && serviceCity == normalizedCity;
    final stateMatches =
        normalizedState.isNotEmpty && serviceState == normalizedState;
    return cityMatches || stateMatches;
  }

  bool get _hasActiveDiscoveryFilters {
    return _selectedAnimal != 'All' ||
        _selectedCategory != 'All' ||
        _searchQuery.trim().isNotEmpty ||
        _selectedRadius != _DiscoveryRadiusFilter.smart;
  }

  String _emptySearchMessage(_DiscoveryPresentation presentation) {
    final query = presentation.searchQuery;
    if (query.isNotEmpty) {
      return "No services found for '$query' with the selected filters.";
    }
    return 'Try changing the animal, service, or radius filters.';
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    const topBarHeight = 126.0;
    final topContentPadding = topInset + (_isTopBarVisible ? topBarHeight : 12);
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);

    return SocialTabBackScope(
      activeTab: SocialAppTab.services,
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true,
        body: Stack(
          children: [
            // The scroll view fills the whole screen so cards can move under the
            // glass overlays. Internal padding preserves access to the first and
            // last interactive elements.
            StreamBuilder<List<ServiceModel>>(
              stream: _activeServicesStream,
              builder: (context, snapshot) {
                final services = snapshot.data ?? const <ServiceModel>[];
                final discoveryPresentation = _buildDiscoveryPresentation(
                  services,
                );
                if (kDebugMode) {
                  debugPrint(
                    'Services discovery debug -> loaded service count: ${services.length}',
                  );
                  debugPrint(
                    'Services discovery debug -> user location available: ${_userLatitude != null && _userLongitude != null}',
                  );
                }

                return ListView(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                    18,
                    topContentPadding,
                    18,
                    bottomContentPadding,
                  ),
                  children: [
                    _ServiceFilterSections(
                      selectedAnimal: _selectedAnimal,
                      animals: _animals,
                      onAnimalSelected: (animal) {
                        if (_selectedAnimal == animal) return;
                        setState(() => _selectedAnimal = animal);
                      },
                      selectedCategory: _selectedCategory,
                      categories: _categories,
                      onCategorySelected: (category) {
                        if (_selectedCategory == category) return;
                        setState(() {
                          _selectedCategory = category;
                          _refreshServicesStream();
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !NetworkStatusService.instance.isOffline)
                      const Padding(
                        padding: EdgeInsets.only(top: 48),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (snapshot.connectionState ==
                            ConnectionState.waiting &&
                        NetworkStatusService.instance.isOffline)
                      const _ServicesEmptyState(
                        icon: Icons.wifi_off_rounded,
                        title: 'You’re offline',
                        message:
                            'Connect to the internet to load latest content.',
                      )
                    else if (snapshot.hasError)
                      _ServicesEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: NetworkStatusService.instance.isOffline
                            ? 'You’re offline'
                            : 'Unable to load services',
                        message: NetworkStatusService.instance.isOffline
                            ? 'Connect to the internet to load latest content.'
                            : 'Please check your connection and try again in a moment.',
                      )
                    else if (services.isEmpty && _hasActiveDiscoveryFilters)
                      _ServicesEmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No services match these filters',
                        message: _emptySearchMessage(discoveryPresentation),
                      )
                    else if (services.isEmpty)
                      _ServicesEmptyState(
                        icon: NetworkStatusService.instance.isOffline
                            ? Icons.wifi_off_rounded
                            : Icons.design_services_outlined,
                        title: NetworkStatusService.instance.isOffline
                            ? 'You’re offline'
                            : 'No services yet',
                        message: NetworkStatusService.instance.isOffline
                            ? 'Connect to the internet to load latest content.'
                            : 'Services will appear here after people publish listings in your marketplace.',
                      )
                    else if (discoveryPresentation.allMatchedCount == 0)
                      _ServicesEmptyState(
                        icon: Icons.search_off_rounded,
                        title: _hasActiveDiscoveryFilters
                            ? 'No services match these filters'
                            : 'No services found',
                        message: _emptySearchMessage(discoveryPresentation),
                      )
                    else if (discoveryPresentation.primaryServices.isEmpty &&
                        discoveryPresentation.secondaryServices.isEmpty)
                      const _ServicesEmptyState(
                        icon: Icons.design_services_outlined,
                        title: 'No services yet',
                        message:
                            'Services will appear here after people publish listings in your marketplace.',
                      )
                    else ...[
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
                          child: _MarketplaceServiceCard(
                            service: entry.service,
                          ),
                        );
                      }),
                      if (discoveryPresentation
                          .secondaryServices
                          .isNotEmpty) ...[
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
                            child: _MarketplaceServiceCard(
                              service: entry.service,
                            ),
                          );
                        }),
                      ],
                    ],
                  ],
                );
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: AnimatedSlide(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                offset: _isTopBarVisible ? Offset.zero : const Offset(0, -1.1),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeInOutCubic,
                  opacity: _isTopBarVisible ? 1 : 0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    scale: _isTopBarVisible ? 1 : 0.97,
                    child: IgnorePointer(
                      ignoring: !_isTopBarVisible,
                      child: _ServicesCollapsibleHeader(
                        topInset: topInset,
                        searchController: _searchController,
                        onSearchChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                        onClearSearch: _searchQuery.isEmpty
                            ? null
                            : () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                        onBackPressed: () =>
                            Navigator.pushReplacementNamed(context, "/home"),
                        onFilterPressed: _showFiltersSheet,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: const SocialBottomNav(
          activeTab: SocialAppTab.services,
        ),
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

class _ServicesCollapsibleHeader extends StatelessWidget {
  final double topInset;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback? onClearSearch;
  final VoidCallback onBackPressed;
  final VoidCallback onFilterPressed;

  const _ServicesCollapsibleHeader({
    required this.topInset,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onBackPressed,
    required this.onFilterPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: EdgeInsets.fromLTRB(18, topInset + 8, 18, 9),
      borderRadius: BorderRadius.zero,
      backgroundColor: AppColors.background.withValues(alpha: 0.74),
      blurSigma: 22,
      border: Border(
        bottom: BorderSide(color: Colors.white.withValues(alpha: 0.58)),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.035),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
      child: Column(
        children: [
          Row(
            children: [
              _HeaderIconButton(
                icon: Icons.arrow_back_rounded,
                onPressed: onBackPressed,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Services',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              _HeaderIconButton(
                icon: Icons.tune_rounded,
                onPressed: onFilterPressed,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.08),
              ),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Search services, providers or areas',
                      hintStyle: TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (onClearSearch != null)
                  IconButton(
                    onPressed: onClearSearch,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.textGrey,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _HeaderIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.72)),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.textDark),
      ),
    );
  }
}

class _ServiceFilterSections extends StatelessWidget {
  final String selectedAnimal;
  final List<String> animals;
  final ValueChanged<String> onAnimalSelected;
  final String selectedCategory;
  final List<String> categories;
  final ValueChanged<String> onCategorySelected;

  const _ServiceFilterSections({
    required this.selectedAnimal,
    required this.animals,
    required this.onAnimalSelected,
    required this.selectedCategory,
    required this.categories,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FilterSectionLabel(label: 'ANIMAL'),
        const SizedBox(height: 6),
        _FilterChipScroller(
          values: animals,
          selectedValue: selectedAnimal,
          onSelected: onAnimalSelected,
        ),
        const SizedBox(height: 12),
        _FilterSectionLabel(label: 'SERVICE'),
        const SizedBox(height: 6),
        _FilterChipScroller(
          values: categories,
          selectedValue: selectedCategory,
          onSelected: onCategorySelected,
        ),
      ],
    );
  }
}

class _FilterSectionLabel extends StatelessWidget {
  final String label;

  const _FilterSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.textGrey,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.0,
      ),
    );
  }
}

class _FilterChipScroller extends StatelessWidget {
  final List<String> values;
  final String selectedValue;
  final ValueChanged<String> onSelected;

  const _FilterChipScroller({
    required this.values,
    required this.selectedValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final value = values[index];
          return _CategoryChip(
            label: value,
            isActive: selectedValue == value,
            onTap: () => onSelected(value),
          );
        },
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
    return Semantics(
      button: true,
      selected: isActive,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 38),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFFFFF3EC) : Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isActive
                    ? AppColors.primary
                    : AppColors.textGrey.withValues(alpha: 0.18),
                width: isActive ? 1.8 : 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: isActive ? 0.035 : 0.02,
                  ),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isActive ? AppColors.primary : AppColors.textDark,
                fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                fontSize: 13,
              ),
            ),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              final imageSize = (constraints.maxWidth * 0.37).clamp(
                112.0,
                150.0,
              );

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: SizedBox(
                        width: imageSize,
                        height: imageSize,
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
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
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
                          const SizedBox(height: 3),
                          LiveUserIdentityResolver(
                            userId: service.ownerUserId,
                            fallbackName: service.ownerName,
                            fallbackUsername: service.ownerUsername,
                            fallbackImageUrl: service.ownerPhotoUrl,
                            placeholderName: 'Service provider',
                            builder: (context, identity) {
                              return Text(
                                'By ${identity.displayName}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            },
                          ),
                          if (service.isSponsorActive) ...[
                            const SizedBox(height: 4),
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
                          const SizedBox(height: 7),
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
                          const SizedBox(height: 8),
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
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
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
                                    fontSize: 13,
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
              );
            },
          ),
        ),
      ),
    );
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
