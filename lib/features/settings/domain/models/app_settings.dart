class AppSettings {
  final bool socialNotificationsEnabled;
  final bool messagePreviewsEnabled;
  final bool bookingNotificationsEnabled;
  final bool hasListedServices;
  final bool showManageServicesOnProfile;
  final bool hasSeenProfileSpotlight;

  const AppSettings({
    required this.socialNotificationsEnabled,
    required this.messagePreviewsEnabled,
    required this.bookingNotificationsEnabled,
    required this.hasListedServices,
    required this.showManageServicesOnProfile,
    required this.hasSeenProfileSpotlight,
  });

  const AppSettings.defaults()
    : socialNotificationsEnabled = true,
      messagePreviewsEnabled = true,
      bookingNotificationsEnabled = true,
      hasListedServices = false,
      showManageServicesOnProfile = false,
      hasSeenProfileSpotlight = false;

  AppSettings copyWith({
    bool? socialNotificationsEnabled,
    bool? messagePreviewsEnabled,
    bool? bookingNotificationsEnabled,
    bool? hasListedServices,
    bool? showManageServicesOnProfile,
    bool? hasSeenProfileSpotlight,
  }) {
    return AppSettings(
      socialNotificationsEnabled:
          socialNotificationsEnabled ?? this.socialNotificationsEnabled,
      messagePreviewsEnabled:
          messagePreviewsEnabled ?? this.messagePreviewsEnabled,
      bookingNotificationsEnabled:
          bookingNotificationsEnabled ?? this.bookingNotificationsEnabled,
      hasListedServices: hasListedServices ?? this.hasListedServices,
      showManageServicesOnProfile:
          showManageServicesOnProfile ?? this.showManageServicesOnProfile,
      hasSeenProfileSpotlight:
          hasSeenProfileSpotlight ?? this.hasSeenProfileSpotlight,
    );
  }
}
