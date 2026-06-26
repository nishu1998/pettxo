import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../domain/models/service_location.dart';

class ServiceLocationPickerScreen extends StatefulWidget {
  final ServiceLocation initialLocation;

  const ServiceLocationPickerScreen({super.key, required this.initialLocation});

  @override
  State<ServiceLocationPickerScreen> createState() =>
      _ServiceLocationPickerScreenState();
}

class _ServiceLocationPickerScreenState
    extends State<ServiceLocationPickerScreen> {
  static const Color _screenBackground = Color(0xFFFCF8F5);
  final TextEditingController _searchController = TextEditingController();
  late LatLng _selectedLatLng;
  String _displayAddress = '';
  bool _isResolvingAddress = false;
  bool _isSearching = false;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _selectedLatLng = LatLng(
      widget.initialLocation.latitude,
      widget.initialLocation.longitude,
    );
    _displayAddress = widget.initialLocation.displayAddress;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _resolveAddress(LatLng target) async {
    setState(() {
      _isResolvingAddress = true;
    });

    try {
      final placemarks = await placemarkFromCoordinates(
        target.latitude,
        target.longitude,
      );
      if (!mounted) return;

      setState(() {
        _displayAddress = _formatPlacemark(placemarks);
      });
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not load an address for this spot.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResolvingAddress = false;
        });
      }
    }
  }

  Future<void> _searchLocation() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _isSearching) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final locations = await locationFromAddress(query);
      if (!mounted) return;
      if (locations.isEmpty) {
        AppFeedback.show(
          context,
          message: 'No matching location found.',
          tone: AppFeedbackTone.info,
        );
        return;
      }

      final match = locations.first;
      final target = LatLng(match.latitude, match.longitude);
      setState(() {
        _selectedLatLng = target;
      });
      await _mapController?.animateCamera(CameraUpdate.newLatLng(target));
      await _resolveAddress(target);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Try a more specific place or landmark.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _confirmLocation() {
    Navigator.pop(
      context,
      ServiceLocation(
        latitude: _selectedLatLng.latitude,
        longitude: _selectedLatLng.longitude,
        displayAddress: _displayAddress.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _screenBackground,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              topInset + 108,
              16,
              bottomInset + 24,
            ),
            child: Column(
              children: [
                _SearchBar(
                  controller: _searchController,
                  isSearching: _isSearching,
                  onSearch: _searchLocation,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: _selectedLatLng,
                            zoom: 15.5,
                          ),
                          myLocationButtonEnabled: false,
                          mapToolbarEnabled: false,
                          zoomControlsEnabled: false,
                          onMapCreated: (controller) {
                            _mapController = controller;
                          },
                          onCameraMove: (position) {
                            _selectedLatLng = position.target;
                          },
                          onCameraIdle: () {
                            _resolveAddress(_selectedLatLng);
                          },
                        ),
                        IgnorePointer(
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.brandGradient,
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isResolvingAddress
                            ? 'Updating selected address...'
                            : _displayAddress,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_selectedLatLng.latitude.toStringAsFixed(5)}, ${_selectedLatLng.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Confirm Location',
                  onPressed: _displayAddress.trim().isEmpty
                      ? null
                      : _confirmLocation,
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: topInset + 10,
            child: Align(
              child: FractionallySizedBox(
                widthFactor: 0.85,
                child: GlassSurface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  backgroundColor: Colors.white.withValues(alpha: 0.72),
                  blurSigma: 20,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
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
                      const Expanded(
                        child: Text(
                          'Pick Location',
                          style: TextStyle(
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
            ),
          ),
        ],
      ),
    );
  }

  String _formatPlacemark(List<Placemark> placemarks) {
    if (placemarks.isEmpty) return 'Selected location';
    final place = placemarks.first;
    final parts = [
      place.name,
      place.street,
      place.subLocality,
      place.locality,
      place.administrativeArea,
    ].where((part) => part != null && part.trim().isNotEmpty).cast<String>();

    return parts.take(4).join(', ');
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isSearching;
  final VoidCallback onSearch;

  const _SearchBar({
    required this.controller,
    required this.isSearching,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: InputDecoration(
              hintText: 'Search area or landmark',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SecondaryButton(
          label: isSearching ? '...' : 'Search',
          onPressed: isSearching ? null : onSearch,
          expand: false,
        ),
      ],
    );
  }
}
