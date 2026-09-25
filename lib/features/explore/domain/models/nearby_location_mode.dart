enum NearbyLocationMode {
  radius,
  savedCityState,
  unavailable;

  static NearbyLocationMode fromResponse({
    required Object? value,
    required bool usedCityStateFallback,
    required double? activeRadiusKm,
  }) {
    switch (value) {
      case 'radius':
        return NearbyLocationMode.radius;
      case 'savedCityState':
        return NearbyLocationMode.savedCityState;
      case 'unavailable':
        return NearbyLocationMode.unavailable;
    }
    if (usedCityStateFallback) {
      return NearbyLocationMode.savedCityState;
    }
    if (activeRadiusKm != null) {
      return NearbyLocationMode.radius;
    }
    return NearbyLocationMode.unavailable;
  }

  static NearbyLocationMode fromAvailableSources({
    required bool hasStoredCoordinates,
    required String savedCity,
    required String savedState,
  }) {
    if (hasStoredCoordinates) return NearbyLocationMode.radius;
    if (savedCity.trim().isNotEmpty || savedState.trim().isNotEmpty) {
      return NearbyLocationMode.savedCityState;
    }
    return NearbyLocationMode.unavailable;
  }

  String? bannerText(double? activeRadiusKm) {
    switch (this) {
      case NearbyLocationMode.radius:
        final radiusKm = activeRadiusKm ?? 50;
        return 'Showing posts within ${radiusKm.toStringAsFixed(0)} km of you.';
      case NearbyLocationMode.savedCityState:
        return 'Showing posts near your saved city/state.';
      case NearbyLocationMode.unavailable:
        return null;
    }
  }
}
