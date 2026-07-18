import 'dart:io';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/live_user_identity_resolver.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../bookings/data/repositories/booking_review_repository.dart';
import '../../../bookings/domain/models/booking_review_model.dart';
import '../../../bookings/presentation/screens/slot_selection_screen.dart';
import '../../../messages/data/repositories/chat_repository.dart';
import '../../../messages/presentation/screens/chat_detail_screen.dart';
import '../../../moderation/presentation/widgets/report_sheet.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../../settings/presentation/screens/legal_policies_screen.dart';
import '../../domain/models/profile_service_listing.dart';
import 'profile_screen.dart';

class ServiceDetailScreen extends StatefulWidget {
  final ProfileServiceListing service;
  final bool showRebookHint;
  final DateTime? suggestedSlotStartAt;

  const ServiceDetailScreen({
    super.key,
    required this.service,
    this.showRebookHint = false,
    this.suggestedSlotStartAt,
  });

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  static const double _topBarHideThreshold = 18;
  static const double _topBarShowThreshold = 12;
  static const double _topBarTopResetOffset = 8;

  final ScrollController _scrollController = ScrollController();
  bool _isTopBarVisible = true;
  double _lastScrollOffset = 0;
  double _scrollDeltaAccumulator = 0;

  ProfileServiceListing get service => widget.service;
  bool get showRebookHint => widget.showRebookHint;
  DateTime? get suggestedSlotStartAt => widget.suggestedSlotStartAt;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
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

  void _openBookingFlow(BuildContext context) {
    if (service.isPausedByVerification) {
      AppSnackbar.warning(
        context,
        message:
            'This service is temporarily unavailable while provider verification is pending.',
      );
      return;
    }
    if (!UserRestrictionService.instance.ensureCanUseBookingFeatures(context)) {
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlotSelectionScreen(
          serviceId: service.id,
          serviceName: service.title,
          price: _resolvedPrice,
          durationMinutes: _resolvedDurationMinutes,
          providerId: service.ownerUserId,
          suggestedSlotStartAt: suggestedSlotStartAt,
          providerName: service.providerDisplayName,
          serviceImageUrl: service.galleryImages.isNotEmpty
              ? service.galleryImages.first
              : service.imageUrl,
        ),
      ),
    );
  }

  int get _resolvedPrice {
    if (service.pricePerSession > 0) return service.pricePerSession;
    final match = RegExp(r'\d+').firstMatch(service.rate.replaceAll(',', ''));
    return int.tryParse(match?.group(0) ?? '') ?? 0;
  }

  int get _resolvedDurationMinutes {
    if (service.durationMinutes > 0) return service.durationMinutes;
    if (service.duration.toLowerCase().contains('whole')) return 24 * 60;
    final match = RegExp(r'\d+').firstMatch(service.duration);
    return int.tryParse(match?.group(0) ?? '') ?? 60;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const topBarHeight = 68.0;
    final topContentPadding = topInset + topBarHeight + 10;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isOwner =
        currentUserId.isNotEmpty && currentUserId == service.ownerUserId;
    final canBook = currentUserId.isNotEmpty && !isOwner;
    final isVerificationPaused = service.isPausedByVerification;
    final canRequestBooking = canBook && !isVerificationPaused;

    return Scaffold(
      backgroundColor: const Color(0xFFFCF8F5),
      extendBody: true,
      body: Stack(
        children: [
          ListView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              18,
              topContentPadding,
              18,
              bottomInset + (canBook ? 132 : 28),
            ),
            children: [
              _ServiceHero(
                service: service,
                isOwner: isOwner,
                canOpenMenu: currentUserId.isNotEmpty && !isOwner,
              ),
              const SizedBox(height: 18),
              _ServiceSummaryCard(
                service: service,
                showRebookHint: showRebookHint,
              ),
              const SizedBox(height: 18),
              _DetailCard(
                title: 'About This Service',
                showDisplayTitle: false,
                children: [
                  Text(
                    service.description,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      height: 1.55,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _DetailRow(
                    label: 'Availability',
                    value: service.availability,
                    valueBold: true,
                    showBottomDivider: true,
                  ),
                  _DetailRow(
                    label: 'Location',
                    value: service.location,
                    valueBold: true,
                  ),
                  const _CancellationPolicyRow(),
                ],
              ),
              if (service.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                _DetailCard(
                  title: 'Booking Notes',
                  children: [
                    Text(
                      service.notes,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        height: 1.55,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              _ServiceReviewsSection(service: service),
              const SizedBox(height: 18),
              _ServiceLocationCard(service: service),
              const SizedBox(height: 22),
              if (canBook && isVerificationPaused)
                Container(
                  margin: const EdgeInsets.only(bottom: 18),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF5F0),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.16),
                    ),
                  ),
                  child: const Text(
                    'This service is temporarily unavailable while provider verification is pending.',
                    style: TextStyle(
                      color: AppColors.textDark,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              offset: _isTopBarVisible ? Offset.zero : const Offset(0, -1.12),
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
                    child: GlassSurface(
                      padding: EdgeInsets.only(top: topInset),
                      borderRadius: BorderRadius.zero,
                      backgroundColor: const Color(
                        0xFFFCF8F5,
                      ).withValues(alpha: 0.72),
                      blurSigma: 22,
                      border: Border(
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.58),
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.035),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                      child: SizedBox(
                        height: topBarHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Row(
                            children: [
                              _HeaderIconButton(
                                icon: Icons.arrow_back_rounded,
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  service.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: canBook
          ? _ServiceBottomActionBar(
              service: service,
              enabled: canRequestBooking,
              isVerificationPaused: isVerificationPaused,
              onBookNow: () => _openBookingFlow(context),
            )
          : null,
    );
  }
}

class _MessageProviderIconButton extends StatefulWidget {
  const _MessageProviderIconButton({
    required this.service,
    required this.enabled,
  });

  final ProfileServiceListing service;
  final bool enabled;

  @override
  State<_MessageProviderIconButton> createState() =>
      _MessageProviderIconButtonState();
}

class _MessageProviderIconButtonState
    extends State<_MessageProviderIconButton> {
  final ChatRepository _chatRepository = ChatRepository();
  bool _isOpening = false;

  Future<void> _openChat() async {
    if (_isOpening) return;
    if (!UserRestrictionService.instance.ensureCanUseSocialFeatures(context)) {
      return;
    }

    if (kDebugMode) {
      debugPrint(
        'ServiceDetail Message debug -> serviceId=${widget.service.id}, '
        'ownerUserId=${widget.service.ownerUserId}, '
        'currentUserId=${FirebaseAuth.instance.currentUser?.uid ?? ''}, '
        'isPaused=${widget.service.isPaused}, '
        'isPausedByVerification=${widget.service.isPausedByVerification}, '
        'title=${widget.service.title}',
      );
    }

    setState(() => _isOpening = true);
    try {
      final chatId = await _chatRepository.startProviderChat(
        serviceId: widget.service.id,
      );
      if (kDebugMode) {
        debugPrint('ServiceDetail Message debug -> opened chatId=$chatId');
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatDetailScreen(chatId: chatId)),
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'ServiceDetail Message debug -> exception=$error\n$stackTrace',
        );
      }
      if (!mounted) return;
      final raw = error.toString();
      final message = raw.contains('message yourself')
          ? 'You cannot message yourself.'
          : raw.contains('not available for chat')
          ? 'This service is not available for chat right now.'
          : raw.contains('cannot start chats')
          ? 'Your account cannot start chats right now.'
          : raw.contains('provider is unavailable')
          ? 'This provider is unavailable for chat right now.'
          : 'Unable to open chat right now.';
      AppFeedback.show(context, message: message, tone: AppFeedbackTone.error);
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.enabled || _isOpening;
    return Semantics(
      button: true,
      label: _isOpening ? 'Opening chat' : 'Message provider',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: disabled ? 0.5 : 1,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: disabled ? null : _openChat,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 50,
              height: 50,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.28),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.035),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: _isOpening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppColors.primary,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceBottomActionBar extends StatelessWidget {
  final ProfileServiceListing service;
  final bool enabled;
  final bool isVerificationPaused;
  final VoidCallback onBookNow;

  const _ServiceBottomActionBar({
    required this.service,
    required this.enabled,
    required this.isVerificationPaused,
    required this.onBookNow,
  });

  @override
  Widget build(BuildContext context) {
    final priceText = service.rate
        .replaceAll(RegExp(r'\s*/\s*session', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+per\s+session', caseSensitive: false), '')
        .trim();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: SizedBox(
          height: 68,
          child: GlassSurface(
            borderRadius: BorderRadius.circular(24),
            backgroundColor: Colors.white.withValues(alpha: 0.88),
            blurSigma: 20,
            border: Border.all(color: Colors.white.withValues(alpha: 0.76)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
            padding: const EdgeInsets.fromLTRB(18, 7, 10, 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 96,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        priceText.isEmpty ? service.rate : priceText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                          height: 1,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        'per session',
                        style: TextStyle(
                          color: Color(0xFF8A8581),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _MessageProviderIconButton(service: service, enabled: enabled),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: _BottomBookButton(
                      label: isVerificationPaused ? 'Unavailable' : 'Book Now',
                      onPressed: enabled ? onBookNow : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceHero extends StatelessWidget {
  final ProfileServiceListing service;
  final bool isOwner;
  final bool canOpenMenu;

  const _ServiceHero({
    required this.service,
    required this.isOwner,
    required this.canOpenMenu,
  });

  @override
  Widget build(BuildContext context) {
    final serviceMode = service.bookingServiceType.isEmpty
        ? service.serviceType
        : service.bookingServiceType;
    final distanceLabel = service.distanceKm > 0
        ? '${service.distanceKm.toStringAsFixed(service.distanceKm < 10 ? 1 : 0)} km away'
        : '';

    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: AspectRatio(
        aspectRatio: 0.92,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ServiceImageCarousel(service: service),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.06),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.28),
                    ],
                    stops: const [0, 0.48, 1],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: _HeroInfoPill(
                icon: distanceLabel.isEmpty
                    ? Icons.design_services_rounded
                    : Icons.near_me_rounded,
                label: distanceLabel.isEmpty
                    ? serviceMode
                    : '$distanceLabel · $serviceMode',
              ),
            ),
            if (service.isSponsorActive)
              const Positioned(
                left: 16,
                bottom: 16,
                child: _HeroInfoPill(
                  icon: Icons.local_fire_department_rounded,
                  label: 'Sponsored',
                ),
              ),
            if (isOwner)
              const Positioned(
                right: 16,
                top: 16,
                child: _HeroInfoPill(
                  icon: Icons.verified_user_outlined,
                  label: 'Your service',
                ),
              )
            else if (canOpenMenu)
              Positioned(
                right: 14,
                top: 14,
                child: _ServiceOverflowMenuButton(service: service),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomBookButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _BottomBookButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: disabled ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(18),
            splashColor: Colors.white.withValues(alpha: 0.14),
            highlightColor: Colors.white.withValues(alpha: 0.06),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.calendar_month_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

class _HeroInfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _HeroInfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: BorderRadius.circular(999),
      backgroundColor: Colors.white.withValues(alpha: 0.74),
      blurSigma: 16,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceSummaryCard extends StatelessWidget {
  final ProfileServiceListing service;
  final bool showRebookHint;

  const _ServiceSummaryCard({
    required this.service,
    required this.showRebookHint,
  });

  @override
  Widget build(BuildContext context) {
    final counts = <String>[
      service.hasReviews
          ? '${service.ratingCount} ${service.ratingCount == 1 ? 'review' : 'reviews'}'
          : 'No reviews yet',
      if (service.completedBookingCount > 0)
        '${service.completedBookingCount} bookings completed',
    ].join(' · ');

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _SummaryPill(label: service.animalType),
              _SummaryPill(label: service.category),
              if (service.hasReviews)
                _SummaryPill(
                  icon: Icons.star_rounded,
                  label: service.ratingAverage.toStringAsFixed(1),
                  isRating: true,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            service.title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            counts,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF8A8581),
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (showRebookHint) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4EC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.refresh_rounded,
                    color: AppColors.primary,
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Booking again with this provider',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          _ProviderCompactCard(service: service),
          const SizedBox(height: 18),
          _InsightStrip(service: service),
        ],
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool isRating;

  const _SummaryPill({this.icon, required this.label, this.isRating = false});

  @override
  Widget build(BuildContext context) {
    final resolvedLabel = label.trim().isEmpty ? 'Not specified' : label.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isRating ? const Color(0xFFFFF4C7) : const Color(0xFFFFEFEA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: isRating ? const Color(0xFF9B6B00) : AppColors.primary,
              size: 14,
            ),
            const SizedBox(width: 5),
          ],
          Text(
            resolvedLabel,
            style: TextStyle(
              color: isRating ? const Color(0xFF9B6B00) : AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCompactCard extends StatelessWidget {
  final ProfileServiceListing service;

  const _ProviderCompactCard({required this.service});

  void _openProviderProfile(BuildContext context) {
    final userId = service.ownerUserId.trim();
    if (userId.isEmpty) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => userId == currentUserId
            ? const ProfileScreen()
            : ProfileScreen(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final providerUserId = service.ownerUserId.trim();
    return LiveUserIdentityResolver(
      userId: providerUserId,
      fallbackName: service.ownerName,
      fallbackUsername: service.ownerUsername,
      fallbackImageUrl: '',
      placeholderName: 'Service provider',
      builder: (context, identity) {
        final card = Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.98),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              _ProviderAvatar(identity: identity),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      identity.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (providerUserId.isNotEmpty) ...[
                const SizedBox(width: 10),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9A928D),
                  size: 24,
                ),
              ],
            ],
          ),
        );

        if (providerUserId.isEmpty) return card;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openProviderProfile(context),
            borderRadius: BorderRadius.circular(22),
            child: card,
          ),
        );
      },
    );
  }
}

class _ProviderAvatar extends StatelessWidget {
  final ResolvedUserIdentity identity;

  const _ProviderAvatar({required this.identity});

  @override
  Widget build(BuildContext context) {
    final imageUrl = identity.imageUrl.trim();
    final fallback = Container(
      color: const Color(0xFFFFE7DE),
      alignment: Alignment.center,
      child: Text(
        identity.initials,
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: 50,
        height: 50,
        child: imageUrl.isEmpty
            ? fallback
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _ServiceLocationCard extends StatelessWidget {
  final ProfileServiceListing service;

  const _ServiceLocationCard({required this.service});

  @override
  Widget build(BuildContext context) {
    return _DetailCard(
      title: 'Location',
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFBF9), Color(0xFFFFF3EC)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      service.location,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 15,
                        height: 1.45,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SecondaryButton(
                label: 'Open in Google Maps',
                icon: Icons.map_outlined,
                onPressed: service.latitude == 0 && service.longitude == 0
                    ? null
                    : () async {
                        final uri = Uri.parse(
                          'https://www.google.com/maps/search/?api=1&query=${service.latitude},${service.longitude}',
                        );
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServiceOverflowMenuButton extends StatelessWidget {
  final ProfileServiceListing service;

  const _ServiceOverflowMenuButton({required this.service});

  void _openProviderProfile(BuildContext context) {
    final userId = service.ownerUserId.trim();
    if (userId.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)),
    );
  }

  void _showActions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(30),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.76),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.68),
                    ),
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
                    children: [
                      if (service.ownerUserId.trim().isNotEmpty) ...[
                        _ServiceActionRow(
                          icon: Icons.person_outline_rounded,
                          label: 'View provider profile',
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _openProviderProfile(context);
                          },
                        ),
                        Divider(
                          height: 1,
                          indent: 20,
                          endIndent: 20,
                          color: AppColors.textGrey.withValues(alpha: 0.12),
                        ),
                      ],
                      _ServiceActionRow(
                        icon: Icons.flag_outlined,
                        label: 'Report service',
                        destructive: true,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          ReportSheet.show(
                            context: context,
                            type: 'service',
                            targetId: service.id,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Service actions',
      child: GlassSurface(
        borderRadius: BorderRadius.circular(18),
        backgroundColor: Colors.white.withValues(alpha: 0.78),
        blurSigma: 16,
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showActions(context),
            borderRadius: BorderRadius.circular(18),
            child: const SizedBox(
              width: 46,
              height: 46,
              child: Icon(Icons.more_horiz_rounded, color: AppColors.textDark),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _ServiceActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : AppColors.textDark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightStrip extends StatelessWidget {
  final ProfileServiceListing service;

  const _InsightStrip({required this.service});

  @override
  Widget build(BuildContext context) {
    final distanceLabel = service.distanceKm > 0
        ? '${service.distanceKm.toStringAsFixed(service.distanceKm < 10 ? 1 : 0)} km'
        : (service.distance.trim().isEmpty ? 'Not set' : service.distance);

    return Row(
      children: [
        Expanded(
          child: _InsightTile(
            icon: Icons.schedule_rounded,
            label: 'Duration',
            value: service.duration,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InsightTile(
            icon: Icons.pets_rounded,
            label: 'Animal',
            value: service.animalType,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _InsightTile(
            icon: Icons.location_on_outlined,
            label: 'Distance',
            value: distanceLabel,
          ),
        ),
      ],
    );
  }
}

class _ServiceReviewsSection extends StatelessWidget {
  final ProfileServiceListing service;

  const _ServiceReviewsSection({required this.service});

  @override
  Widget build(BuildContext context) {
    final reviewRepository = BookingReviewRepository();

    return StreamBuilder<List<BookingReviewModel>>(
      stream: reviewRepository.watchServiceReviews(service.id, limit: 20),
      builder: (context, snapshot) {
        final allReviews = snapshot.data ?? const <BookingReviewModel>[];
        final approvedReviews = allReviews
            .where((review) => review.isApprovedForPublicDisplay)
            .toList(growable: false);
        final latestReviews = approvedReviews.take(3).toList(growable: false);
        final hasMoreReviews = approvedReviews.length > 3;

        return _DetailCard(
          title: 'Reviews',
          showDisplayTitle: false,
          children: [
            Text(
              service.hasReviews
                  ? '⭐ ${service.ratingAverage.toStringAsFixed(1)} · ${service.ratingCount} ${service.ratingCount == 1 ? 'review' : 'reviews'}'
                  : 'No reviews yet',
              style: TextStyle(
                color: service.hasReviews
                    ? AppColors.textDark
                    : AppColors.textGrey,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            if (!service.hasReviews)
              const Text(
                'Be the first pet parent to review this service.',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              )
            else if (snapshot.connectionState == ConnectionState.waiting &&
                approvedReviews.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (latestReviews.isEmpty)
              const Text(
                'No approved reviews yet.',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 13.5,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              )
            else ...[
              ...latestReviews.map(
                (review) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ReviewPreviewCard(review: review),
                ),
              ),
              if (hasMoreReviews) ...[
                const SizedBox(height: 14),
                SecondaryButton(
                  label: 'View all reviews',
                  size: AppButtonSize.compact,
                  onPressed: () => _showAllReviewsSheet(
                    context: context,
                    service: service,
                    reviews: approvedReviews,
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

void _showAllReviewsSheet({
  required BuildContext context,
  required ProfileServiceListing service,
  required List<BookingReviewModel> reviews,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) {
      final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
      final safeBottom = MediaQuery.paddingOf(context).bottom;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.78,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFCF8F5),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'All Reviews',
                              style: TextStyle(
                                color: AppColors.textDark,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      Text(
                        service.hasReviews
                            ? '⭐ ${service.ratingAverage.toStringAsFixed(1)} · ${service.ratingCount} ${service.ratingCount == 1 ? 'review' : 'reviews'}'
                            : 'No reviews yet',
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + safeBottom),
                    itemCount: reviews.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _ReviewPreviewCard(review: reviews[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ReviewPreviewCard extends StatelessWidget {
  final BookingReviewModel review;

  const _ReviewPreviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final reviewerLabel = review.reviewerFirstName.isNotEmpty
        ? review.reviewerFirstName
        : 'Pet parent';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0E8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  reviewerLabel.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  reviewerLabel,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _ReviewStars(rating: review.rating),
            ],
          ),
          if (review.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              review.comment.trim(),
              style: const TextStyle(
                color: AppColors.textDark,
                height: 1.45,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (review.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: review.tags
                  .map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1EA),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  })
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: SecondaryButton(
              label: 'Report review',
              icon: Icons.outlined_flag_rounded,
              size: AppButtonSize.compact,
              expand: false,
              onPressed: FirebaseAuth.instance.currentUser == null
                  ? null
                  : () => ReportSheet.show(
                      context: context,
                      type: 'review',
                      targetId: review.id,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewStars extends StatelessWidget {
  final int rating;

  const _ReviewStars({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        return Padding(
          padding: EdgeInsets.only(left: index == 0 ? 0 : 2),
          child: Icon(
            index < rating ? Icons.star_rounded : Icons.star_border_rounded,
            size: 16,
            color: AppColors.primary,
          ),
        );
      }),
    );
  }
}

class _InsightTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InsightTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceImageCarousel extends StatefulWidget {
  final ProfileServiceListing service;

  const _ServiceImageCarousel({required this.service});

  @override
  State<_ServiceImageCarousel> createState() => _ServiceImageCarouselState();
}

class _ServiceImageCarouselState extends State<_ServiceImageCarousel> {
  late final PageController _pageController;
  int _activePage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.service.galleryImages;
    if (kDebugMode) {
      debugPrint(
        'ServiceDetail gallery debug -> imageUrl: ${widget.service.imageUrl}',
      );
      debugPrint(
        'ServiceDetail gallery debug -> photoPaths: ${widget.service.photoPaths}',
      );
      debugPrint(
        'ServiceDetail gallery debug -> galleryImages: ${widget.service.galleryImages}',
      );
      debugPrint(
        'ServiceDetail gallery debug -> galleryImages.length: ${images.length}',
      );
    }
    if (images.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.brandGradientDiagonal),
        child: Center(
          child: Icon(Icons.pets_rounded, color: Colors.white, size: 44),
        ),
      );
    }

    if (images.length == 1) {
      return _ServiceImageFrame(imagePath: images.first);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.horizontal,
          physics: const PageScrollPhysics(),
          allowImplicitScrolling: true,
          itemCount: images.length,
          onPageChanged: (index) {
            if (!mounted) return;
            setState(() => _activePage = index);
          },
          itemBuilder: (context, index) {
            return _ServiceImageFrame(
              key: ValueKey('${widget.service.id}_${images[index]}'),
              imagePath: images[index],
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: IgnorePointer(
            child: GlassSurface(
              borderRadius: BorderRadius.circular(999),
              backgroundColor: Colors.white.withValues(alpha: 0.74),
              blurSigma: 14,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(images.length, (index) {
                  final isActive = index == _activePage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: isActive ? 18 : 6,
                    height: 6,
                    margin: EdgeInsets.only(
                      right: index == images.length - 1 ? 0 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primary
                          : AppColors.textGrey.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceImageFrame extends StatelessWidget {
  final String imagePath;

  const _ServiceImageFrame({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final path = imagePath.trim();
    if (path.isEmpty) {
      return const DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.brandGradientDiagonal),
        child: Center(
          child: Icon(Icons.pets_rounded, color: Colors.white, size: 44),
        ),
      );
    }

    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const DecoratedBox(
          decoration: BoxDecoration(gradient: AppColors.brandGradientDiagonal),
          child: Center(
            child: Icon(Icons.pets_rounded, color: Colors.white, size: 44),
          ),
        ),
      );
    }

    return Image.file(
      File(path),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.brandGradientDiagonal),
        child: Center(
          child: Icon(Icons.pets_rounded, color: Colors.white, size: 44),
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final bool showDisplayTitle;

  const _DetailCard({
    required this.title,
    required this.children,
    this.showDisplayTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
            ),
          ),
          if (showDisplayTitle) ...[
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _CancellationPolicyRow extends StatelessWidget {
  const _CancellationPolicyRow();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(height: 24, color: AppColors.textGrey.withValues(alpha: 0.14)),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Cancellation',
                style: TextStyle(
                  color: Color(0xFF8A8581),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(
                context,
                LegalPoliciesCatalog.cancellationPolicy.routeName,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'View policy',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool valueBold;
  final bool showBottomDivider;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueBold = false,
    this.showBottomDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontWeight: valueBold ? FontWeight.w900 : FontWeight.w600,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          if (showBottomDivider)
            Divider(
              height: 24,
              color: AppColors.textGrey.withValues(alpha: 0.14),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }
}
