import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/service_location.dart';

class ServiceLocationCard extends StatelessWidget {
  final ServiceLocation? location;
  final bool isLoading;
  final String helperText;
  final String? errorText;
  final String? statusMessage;
  final bool isHighlighted;
  final VoidCallback onChangeLocation;
  final VoidCallback onEditAddress;

  const ServiceLocationCard({
    super.key,
    required this.location,
    required this.isLoading,
    required this.helperText,
    required this.onChangeLocation,
    required this.onEditAddress,
    this.errorText,
    this.statusMessage,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasLocation = location != null && location!.displayAddress.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Location',
          style: TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFCFBFA),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: errorText != null
                  ? Colors.redAccent
                  : isHighlighted
                  ? AppColors.primary
                  : Colors.transparent,
              width: isHighlighted ? 1.4 : 1,
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
                      hasLocation
                          ? location!.displayAddress
                          : (statusMessage ??
                              'Location access required. Please enable location or select manually.'),
                      style: TextStyle(
                        color: hasLocation
                            ? AppColors.textDark
                            : AppColors.textGrey,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (hasLocation)
                GestureDetector(
                  onTap: onChangeLocation,
                  child: SizedBox(
                    height: 170,
                    width: double.infinity,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        children: [
                          IgnorePointer(
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: LatLng(
                                  location!.latitude,
                                  location!.longitude,
                                ),
                                zoom: 15.5,
                              ),
                              myLocationButtonEnabled: false,
                              zoomControlsEnabled: false,
                              mapToolbarEnabled: false,
                              liteModeEnabled: true,
                              markers: {
                                Marker(
                                  markerId: const MarkerId('service-location'),
                                  position: LatLng(
                                    location!.latitude,
                                    location!.longitude,
                                  ),
                                ),
                              },
                            ),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.touch_app_rounded,
                                    size: 14,
                                    color: AppColors.primary,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Tap map to change',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: onChangeLocation,
                  child: Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.12),
                          Colors.white,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          color: AppColors.primary,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap the map area to choose a location.',
                          style: TextStyle(
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                helperText,
                style: const TextStyle(
                  color: AppColors.textGrey,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Center(
                child: GestureDetector(
                  onTap: hasLocation ? onEditAddress : null,
                  child: Text(
                    'Edit address',
                    style: TextStyle(
                      color: hasLocation
                          ? AppColors.primary
                          : AppColors.textGrey.withValues(alpha: 0.7),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      decoration:
                          hasLocation ? TextDecoration.underline : null,
                      decorationColor: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
