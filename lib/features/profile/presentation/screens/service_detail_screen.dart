import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../bookings/data/repositories/booking_review_repository.dart';
import '../../../bookings/domain/models/booking_review_model.dart';
import '../../../bookings/presentation/screens/slot_selection_screen.dart';
import '../../../moderation/presentation/widgets/report_sheet.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../domain/models/profile_service_listing.dart';

class ServiceDetailScreen extends StatelessWidget {
  final ProfileServiceListing service;
  final bool showRebookHint;
  final DateTime? suggestedSlotStartAt;

  const ServiceDetailScreen({
    super.key,
    required this.service,
    this.showRebookHint = false,
    this.suggestedSlotStartAt,
  });

  void _openBookingFlow(BuildContext context) {
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
    final topContentPadding = topInset + 108;
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isOwner =
        currentUserId.isNotEmpty && currentUserId == service.ownerUserId;
    final canBook = currentUserId.isNotEmpty && !isOwner;

    return Scaffold(
      backgroundColor: const Color(0xFFFCF8F5),
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              18,
              topContentPadding,
              18,
              bottomInset + 28,
            ),
            children: [
              _ServiceHero(
                service: service,
                canBook: canBook,
                isOwner: isOwner,
                showRebookHint: showRebookHint,
                onBookNow: () => _openBookingFlow(context),
              ),
              const SizedBox(height: 18),
              _InsightStrip(service: service),
              const SizedBox(height: 18),
              _DetailCard(
                title: 'Service Overview',
                children: [
                  _DetailRow(label: 'Category', value: service.category),
                  _DetailRow(label: 'Animal', value: service.animalType),
                  _DetailRow(
                    label: 'Service type',
                    value: service.bookingServiceType,
                  ),
                  _DetailRow(label: 'Price', value: service.rate),
                  _DetailRow(label: 'Duration', value: service.duration),
                  _DetailRow(
                    label: 'Availability',
                    value: service.availability,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _DetailCard(
                title: 'Description',
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
              _DetailCard(
                title: 'Location',
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFAF7),
                      borderRadius: BorderRadius.circular(20),
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
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.location_on_outlined,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                service.location,
                                style: const TextStyle(
                                  color: AppColors.textDark,
                                  fontSize: 15,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SecondaryButton(
                          label: 'Open in Google Maps',
                          icon: Icons.map_outlined,
                          onPressed:
                              service.latitude == 0 && service.longitude == 0
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
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: SecondaryButton(
                  label: 'Report service',
                  icon: Icons.flag_outlined,
                  size: AppButtonSize.compact,
                  expand: false,
                  onPressed: currentUserId.isEmpty || isOwner
                      ? null
                      : () => ReportSheet.show(
                          context: context,
                          type: 'service',
                          targetId: service.id,
                        ),
                ),
              ),
              const SizedBox(height: 22),
              if (canBook)
                GradientButton(
                  label: 'Book Now',
                  icon: Icons.calendar_month_rounded,
                  onPressed: () => _openBookingFlow(context),
                ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: topInset + 10,
            child: GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              borderRadius: BorderRadius.circular(24),
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              blurSigma: 20,
              border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 22,
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
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      service.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceHero extends StatelessWidget {
  final ProfileServiceListing service;
  final bool canBook;
  final bool isOwner;
  final bool showRebookHint;
  final VoidCallback onBookNow;

  const _ServiceHero({
    required this.service,
    required this.canBook,
    required this.isOwner,
    required this.showRebookHint,
    required this.onBookNow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFDFC), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: AspectRatio(
              aspectRatio: 1.25,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _ServiceImageCarousel(service: service),
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.18),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    top: 16,
                    child: IgnorePointer(
                      child: GlassSurface(
                        borderRadius: BorderRadius.circular(999),
                        backgroundColor: Colors.white.withValues(alpha: 0.78),
                        blurSigma: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.design_services_rounded,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              service.bookingServiceType.isEmpty
                                  ? service.serviceType
                                  : service.bookingServiceType,
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (service.isSponsorActive) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF2EA),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'Sponsored',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (canBook)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: GradientButton(
                label: 'Book Now',
                icon: Icons.calendar_month_rounded,
                onPressed: onBookNow,
              ),
            )
          else if (isOwner)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.14),
                  ),
                ),
                child: const Text(
                  'Your service',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  service.serviceType,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (showRebookHint) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
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
                const SizedBox(height: 10),
                _ProviderIdentityRow(service: service),
                const SizedBox(height: 10),
                Text(
                  service.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    height: 1.45,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        service.bookingServiceType.isEmpty
                            ? service.serviceType
                            : service.bookingServiceType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      service.rate,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightStrip extends StatelessWidget {
  final ProfileServiceListing service;

  const _InsightStrip({required this.service});

  @override
  Widget build(BuildContext context) {
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
            icon: Icons.category_rounded,
            label: 'Category',
            value: service.category,
          ),
        ),
      ],
    );
  }
}

class _ProviderIdentityRow extends StatefulWidget {
  final ProfileServiceListing service;

  const _ProviderIdentityRow({required this.service});

  @override
  State<_ProviderIdentityRow> createState() => _ProviderIdentityRowState();
}

class _ProviderIdentityRowState extends State<_ProviderIdentityRow> {
  String? _resolvedProviderName;

  @override
  void initState() {
    super.initState();
    _resolvedProviderName = _snapshotProviderLabel;
    if (_resolvedProviderName == 'Service provider') {
      _loadProviderNameFallback();
    }
  }

  String get _snapshotProviderLabel {
    final ownerName = widget.service.ownerName.trim();
    if (ownerName.isNotEmpty) return ownerName;
    final ownerUsername = widget.service.ownerUsername.trim().replaceFirst(
      '@',
      '',
    );
    if (ownerUsername.isNotEmpty) return ownerUsername;
    return 'Service provider';
  }

  Future<void> _loadProviderNameFallback() async {
    final ownerUserId = widget.service.ownerUserId.trim();
    if (ownerUserId.isEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerUserId)
          .get();
      final data = snapshot.data();
      if (data == null || !mounted) return;
      final name = (data['name'] as String? ?? '').trim();
      final username = (data['username'] as String? ?? '').trim().replaceFirst(
        '@',
        '',
      );
      final resolved = name.isNotEmpty
          ? name
          : username.isNotEmpty
          ? username
          : 'Service provider';
      setState(() => _resolvedProviderName = resolved);
    } catch (_) {
      // Detail UI can gracefully keep the generic provider fallback.
    }
  }

  // TODO(nishant): Add a real "Report user" entry point when Pettxo has a
  // public provider profile screen. The current profile screen is the owner's
  // private area, so reporting from there would be the wrong UX.

  @override
  Widget build(BuildContext context) {
    final providerName = _resolvedProviderName ?? 'Service provider';
    return Row(
      children: [
        const Icon(
          Icons.person_outline_rounded,
          color: AppColors.textGrey,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Provided by $providerName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 18),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              height: 1.35,
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

  const _DetailCard({required this.title, required this.children});

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
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
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
              style: const TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
