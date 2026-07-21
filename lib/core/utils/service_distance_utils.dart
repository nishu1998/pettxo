import 'package:geolocator/geolocator.dart';

class ServiceDistanceUtils {
  const ServiceDistanceUtils._();

  static bool isValidLatitude(double value) {
    return value.isFinite && value >= -90 && value <= 90;
  }

  static bool isValidLongitude(double value) {
    return value.isFinite && value >= -180 && value <= 180;
  }

  static bool hasUsableCoordinates(double latitude, double longitude) {
    if (!isValidLatitude(latitude) || !isValidLongitude(longitude)) {
      return false;
    }

    return latitude != 0 || longitude != 0;
  }

  static double? calculateDistanceKm({
    required double userLatitude,
    required double userLongitude,
    required double serviceLatitude,
    required double serviceLongitude,
  }) {
    if (!hasUsableCoordinates(userLatitude, userLongitude) ||
        !hasUsableCoordinates(serviceLatitude, serviceLongitude)) {
      return null;
    }

    final distanceMeters = Geolocator.distanceBetween(
      userLatitude,
      userLongitude,
      serviceLatitude,
      serviceLongitude,
    );

    if (!distanceMeters.isFinite || distanceMeters <= 0) {
      return null;
    }

    return distanceMeters / 1000;
  }

  static double? normalizeDistanceKm(double? value) {
    if (value == null || !value.isFinite || value <= 0) {
      return null;
    }

    return value;
  }

  static String formatDistance(double? distanceKm) {
    final normalizedDistanceKm = normalizeDistanceKm(distanceKm);
    if (normalizedDistanceKm == null) return '';

    final distanceMeters = normalizedDistanceKm * 1000;
    if (distanceMeters < 100) {
      return '100 m';
    }
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    if (normalizedDistanceKm < 10) {
      return '${normalizedDistanceKm.toStringAsFixed(1)} km';
    }
    return '${normalizedDistanceKm.toStringAsFixed(0)} km';
  }
}
