import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_settings.dart';

class SettingsService {
  static const _socialNotificationsKey = 'settings_social_notifications';
  static const _messagePreviewsKey = 'settings_message_previews';
  static const _bookingNotificationsKey = 'settings_booking_notifications';
  static const _hasListedServicesKey = 'settings_has_listed_services';
  static const _showManageServicesKey = 'settings_show_manage_services';

  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    return AppSettings(
      socialNotificationsEnabled:
          prefs.getBool(_socialNotificationsKey) ?? true,
      messagePreviewsEnabled: prefs.getBool(_messagePreviewsKey) ?? true,
      bookingNotificationsEnabled:
          prefs.getBool(_bookingNotificationsKey) ?? true,
      hasListedServices: prefs.getBool(_hasListedServicesKey) ?? false,
      showManageServicesOnProfile:
          prefs.getBool(_showManageServicesKey) ?? false,
    );
  }

  Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      _socialNotificationsKey,
      settings.socialNotificationsEnabled,
    );
    await prefs.setBool(_messagePreviewsKey, settings.messagePreviewsEnabled);
    await prefs.setBool(
      _bookingNotificationsKey,
      settings.bookingNotificationsEnabled,
    );
    await prefs.setBool(_hasListedServicesKey, settings.hasListedServices);
    await prefs.setBool(
      _showManageServicesKey,
      settings.showManageServicesOnProfile && settings.hasListedServices,
    );
  }
}
