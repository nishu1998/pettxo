import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../feed/data/repositories/feed_mock_repository.dart';
import '../../../feed/domain/models/feed_post.dart';
import '../../domain/models/profile_service_listing.dart';
import '../../domain/models/user_profile.dart';

class ProfileContentRepository {
  static const _deletedServicesKey = 'profile_deleted_services';
  static const _pausedServicesKey = 'profile_paused_services';
  static const _pauseAllServicesKey = 'profile_pause_all_services';
  static const _customServicesPrefix = 'profile_custom_services_';

  const ProfileContentRepository();

  List<FeedPost> getPostsForProfile(UserProfile profile) {
    final username = profile.displayUsername.toLowerCase();
    if (username.isEmpty) return const [];

    return const FeedMockRepository().getPosts().where((post) {
      return post.username.toLowerCase() == username;
    }).toList();
  }

  Future<List<ProfileServiceListing>> getServicesForProfile(
    UserProfile profile,
  ) async {

    final prefs = await SharedPreferences.getInstance();
    final deletedIds = _readStringSet(prefs, _deletedServicesKey);
    final pausedIds = _readStringSet(prefs, _pausedServicesKey);
    final pauseAll = prefs.getBool(_pauseAllServicesKey) ?? false;

    final services = [
      if (profile.isServiceProvider) ..._seedServices(profile),
      ..._readCustomServices(prefs, profile.uid),
    ];

    return services.where((service) => !deletedIds.contains(service.id)).map((
      service,
    ) {
      return service.copyWith(
        isPaused: pauseAll || pausedIds.contains(service.id),
      );
    }).toList();
  }

  Future<void> addServiceForProfile(
    UserProfile profile,
    ProfileServiceListing service,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final customServices = _readCustomServices(prefs, profile.uid);

    customServices.add(service);

    await prefs.setString(
      _customServicesKey(profile.uid),
      jsonEncode(customServices.map((item) => item.toMap()).toList()),
    );
  }

  Future<void> setServicePaused(String serviceId, bool isPaused) async {
    final prefs = await SharedPreferences.getInstance();
    final pausedIds = _readStringSet(prefs, _pausedServicesKey);

    if (isPaused) {
      pausedIds.add(serviceId);
    } else {
      pausedIds.remove(serviceId);
    }

    await prefs.setString(_pausedServicesKey, jsonEncode(pausedIds.toList()));
  }

  Future<void> deleteService(String serviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final deletedIds = _readStringSet(prefs, _deletedServicesKey);
    final pausedIds = _readStringSet(prefs, _pausedServicesKey);

    deletedIds.add(serviceId);
    pausedIds.remove(serviceId);

    await prefs.setString(_deletedServicesKey, jsonEncode(deletedIds.toList()));
    await prefs.setString(_pausedServicesKey, jsonEncode(pausedIds.toList()));
  }

  Future<void> pauseAllServices() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pauseAllServicesKey, true);
  }

  Set<String> _readStringSet(SharedPreferences prefs, String key) {
    final rawValue = prefs.getString(key);
    if (rawValue == null || rawValue.isEmpty) return <String>{};

    final decoded = jsonDecode(rawValue);
    if (decoded is! List) return <String>{};

    return decoded.whereType<String>().toSet();
  }

  List<ProfileServiceListing> _readCustomServices(
    SharedPreferences prefs,
    String uid,
  ) {
    final rawValue = prefs.getString(_customServicesKey(uid));
    if (rawValue == null || rawValue.isEmpty) return [];

    final decoded = jsonDecode(rawValue);
    if (decoded is! List) return [];

    return decoded
        .whereType<Map>()
        .map((item) {
          return ProfileServiceListing.fromMap(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .where((service) => service.id.isNotEmpty)
        .toList();
  }

  String _customServicesKey(String uid) => '$_customServicesPrefix$uid';

  List<ProfileServiceListing> _seedServices(UserProfile profile) {
    final ownerName = profile.name.isEmpty ? 'Pettxo Provider' : profile.name;

    return [
      ProfileServiceListing(
        id: '${profile.uid}_grooming',
        title: '$ownerName Grooming',
        serviceType: 'Grooming',
        animalType: 'Dog',
        category: 'Grooming',
        serviceRadiusKm: 10,
        bookingServiceType: 'At provider location',
        latitude: 12.9716,
        longitude: 77.5946,
        description: 'Gentle grooming, bath, brushing, and coat care.',
        rate: '\$45-80',
        location: profile.location.isEmpty ? 'Nearby' : profile.location,
        availability: 'Mon, Wed, Fri - 10:00 AM to 4:00 PM',
        duration: '60-90 min',
        petSize: 'Small to large pets',
        rating: '4.9',
        distance: profile.location.isEmpty ? 'Nearby' : profile.location,
        imageUrl:
            'https://images.unsplash.com/photo-1518717758536-85ae29035b6d?auto=format&fit=crop&w=700&q=80',
      ),
      ProfileServiceListing(
        id: '${profile.uid}_walking',
        title: 'Walk & care visits',
        serviceType: 'Walking',
        animalType: 'Dog',
        category: 'Walking',
        serviceRadiusKm: 8,
        bookingServiceType: 'Home visit available',
        latitude: 12.9716,
        longitude: 77.5946,
        description: 'Daily walks, feeding visits, and pet check-ins.',
        rate: '\$20/walk',
        location: profile.location.isEmpty ? 'Nearby' : profile.location,
        availability: 'Daily - 7:00 AM to 7:00 PM',
        duration: '30-45 min',
        petSize: 'All friendly pets',
        rating: '4.8',
        distance: profile.location.isEmpty ? 'Nearby' : profile.location,
        imageUrl:
            'https://images.unsplash.com/photo-1548199973-03cce0bbc87b?auto=format&fit=crop&w=700&q=80',
      ),
    ];
  }
}
