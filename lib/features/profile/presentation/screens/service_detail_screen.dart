import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../bookings/presentation/screens/slot_selection_screen.dart';
import '../../domain/models/profile_service_listing.dart';

class ServiceDetailScreen extends StatelessWidget {
  final ProfileServiceListing service;

  const ServiceDetailScreen({super.key, required this.service});

  void _openBookingFlow(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SlotSelectionScreen(
          serviceId: service.id,
          serviceName: service.title,
          price: _resolvedPrice,
          durationMinutes: _resolvedDurationMinutes,
          providerId: service.ownerUserId,
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
                        GestureDetector(
                          onTap: service.latitude == 0 && service.longitude == 0
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.24,
                                  ),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.map_outlined,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Open in Google Maps',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
  final VoidCallback onBookNow;

  const _ServiceHero({
    required this.service,
    required this.canBook,
    required this.isOwner,
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
