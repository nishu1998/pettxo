import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../feed/domain/models/feed_post.dart';
import '../../../feed/presentation/widgets/feed_post_card.dart';
import '../../domain/models/profile_service_listing.dart';
import '../screens/service_detail_screen.dart';

class ProfileSectionTabs extends StatelessWidget {
  final int selectedIndex;
  final bool showServices;
  final ValueChanged<int> onChanged;

  const ProfileSectionTabs({
    super.key,
    required this.selectedIndex,
    required this.showServices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ProfileTabButton(
              label: 'Posts',
              isActive: selectedIndex == 0,
              onTap: () => onChanged(0),
            ),
          ),
          if (showServices)
            Expanded(
              child: _ProfileTabButton(
                label: 'Services',
                isActive: selectedIndex == 1,
                onTap: () => onChanged(1),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileTabButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ProfileTabButton({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isActive ? AppColors.textDark : AppColors.textGrey,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class ProfilePostsSection extends StatelessWidget {
  final List<FeedPost> posts;

  const ProfilePostsSection({super.key, required this.posts});

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const EmptyProfileSection(
        icon: Icons.grid_view_rounded,
        title: 'No posts yet',
        message:
            'Share your first pet story, service update, or happy moment so followers have something to discover here.',
      );
    }

    return Column(
      children: posts.map((post) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: FeedPostCard(post: post),
        );
      }).toList(),
    );
  }
}

class ProfileServicesSection extends StatelessWidget {
  final List<ProfileServiceListing> services;
  final bool canManage;
  final VoidCallback onAdd;
  final VoidCallback onManage;

  const ProfileServicesSection({
    super.key,
    required this.services,
    required this.canManage,
    required this.onAdd,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canManage) ...[
          Row(
            children: [
              Expanded(
                child: GradientButton(
                  label: 'Add Service',
                  icon: Icons.add_rounded,
                  onPressed: onAdd,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SecondaryButton(
                  label: 'Manage',
                  icon: Icons.tune_rounded,
                  onPressed: onManage,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (services.isEmpty)
          const EmptyProfileSection(
            icon: Icons.design_services_outlined,
            title: 'No services listed',
            message:
                'Add your first service to start showing visitors what you offer and encourage bookings from your profile.',
          )
        else
        ...services.map((service) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _ProfileServiceCard(service: service),
          );
        }),
      ],
    );
  }
}

class _ProfileServiceCard extends StatelessWidget {
  final ProfileServiceListing service;

  const _ProfileServiceCard({required this.service});

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
              builder: (_) => ServiceDetailScreen(service: service),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
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
                  width: 116,
                  height: 158,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (service.imageUrl.isEmpty)
                        _ServiceImageFallback(service: service)
                      else if (service.imageUrl.startsWith('http'))
                        Image.network(
                          service.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _ServiceImageFallback(service: service);
                          },
                        )
                      else
                        Image.file(
                          File(service.imageUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _ServiceImageFallback(service: service);
                          },
                        ),
                      if (service.isPaused)
                        Container(color: Colors.black.withValues(alpha: 0.36)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              service.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          if (service.isPaused) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.textGrey.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'Paused',
                                style: TextStyle(
                                  color: AppColors.textGrey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        service.serviceType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
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
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          service.rate,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppColors.textDark,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            color: AppColors.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: GestureDetector(
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
                              child: Text(
                                service.location.isEmpty
                                    ? service.distance
                                    : service.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.open_in_new_rounded,
                            color: AppColors.primary,
                            size: 14,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.schedule_rounded,
                            color: AppColors.textGrey,
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              service.duration.isEmpty
                                  ? service.availability
                                  : '${service.duration} - ${service.petSize}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
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
}

class _ServiceImageFallback extends StatelessWidget {
  final ProfileServiceListing service;

  const _ServiceImageFallback({required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradientDiagonal,
      ),
      child: Center(
        child: service.photoPaths.isNotEmpty
            ? const Icon(
                Icons.photo_library_rounded,
                color: Colors.white,
                size: 36,
              )
            : const Icon(
                Icons.pets_rounded,
                color: Colors.white,
                size: 36,
              ),
      ),
    );
  }
}

class ManageServiceTile extends StatelessWidget {
  final ProfileServiceListing service;
  final VoidCallback onPause;
  final VoidCallback onDelete;

  const ManageServiceTile({
    super.key,
    required this.service,
    required this.onPause,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCFA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  service.isPaused ? 'Paused' : 'Active',
                  style: TextStyle(
                    color: service.isPaused
                        ? AppColors.textGrey
                        : AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onPause,
            child: Text(service.isPaused ? 'Resume' : 'Pause'),
          ),
          IconButton(
            onPressed: onDelete,
            color: Colors.redAccent,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class EmptyProfileSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyProfileSection({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.primary, size: 34),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
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
