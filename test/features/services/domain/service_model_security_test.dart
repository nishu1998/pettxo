import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/services/domain/models/service_model.dart';

ServiceModel buildService() => const ServiceModel(
  id: 'service-1',
  ownerUserId: 'provider-1',
  ownerName: 'Provider',
  ownerUsername: 'provider',
  ownerPhotoUrl: '',
  ownerCity: 'Mumbai',
  ownerState: 'Maharashtra',
  title: 'Dog Walking',
  animalType: 'Dog',
  category: 'Walking',
  description: 'Safe walks',
  privateNotes: 'Gate code 1234',
  pricePerSession: 500,
  currency: 'INR',
  schedulingMode: 'fixedDuration',
  sessionDurationMinutes: 60,
  capacity: 2,
  availableDays: ['monday'],
  startMinutes: 540,
  endMinutes: 1020,
  sameForAllDays: true,
  serviceType: 'atProviderLocation',
  displayAddress: 'Exact building, Mumbai',
  latitude: 19.076,
  longitude: 72.8777,
  city: 'Mumbai',
  state: 'Maharashtra',
  photoUrls: [],
  primaryPhotoUrl: '',
  status: 'active',
  isActive: true,
  isDeleted: false,
  isPaused: false,
  moderationStatus: 'pending',
  isVisibleToMarketplace: true,
  providerVerificationStatus: 'pending',
  ratingAverage: 0,
  ratingCount: 0,
  createdAt: null,
  updatedAt: null,
  publishedAt: null,
);

void main() {
  test('marketplace service payload contains only coarse public location', () {
    final payload = buildService().toCreateMap();
    final location = payload['location']! as Map<String, dynamic>;

    expect(payload, isNot(contains('privateNotes')));
    expect(location, isNot(contains('displayAddress')));
    expect(location, isNot(contains('latitude')));
    expect(location, isNot(contains('longitude')));
    expect(location['approximateLatitude'], 19.08);
    expect(location['approximateLongitude'], 72.88);
    expect(location['geohash'], hasLength(5));
  });

  test('private service payload retains exact booking and owner details', () {
    final payload = buildService().toPrivateCreateMap('service-1');
    final location = payload['location']! as Map<String, dynamic>;

    expect(payload['ownerUserId'], 'provider-1');
    expect(payload['privateNotes'], 'Gate code 1234');
    expect(location['displayAddress'], 'Exact building, Mumbai');
    expect(location['latitude'], 19.076);
    expect(location['longitude'], 72.8777);
  });

  test(
    'detail listing uses public service city and state instead of owner location',
    () {
      final service = ServiceModel.fromMap('service-pune', {
        'ownerUserId': 'provider-1',
        'ownerSnapshot': {
          'name': 'Provider',
          'city': 'Nagpur',
          'state': 'Maharashtra',
        },
        'title': 'Dog Walking',
        'location': {
          'city': 'Pune',
          'state': 'Maharashtra',
          'approximateLatitude': 18.52,
          'approximateLongitude': 73.86,
        },
        'distanceKm': 12.5,
      });

      final listing = service.toProfileListing();

      expect(service.ownerCity, 'Nagpur');
      expect(service.city, 'Pune');
      expect(listing.location, 'Pune, Maharashtra');
      expect(listing.publicLocationLabel, 'Pune, Maharashtra');
      expect(listing.location, isNot(contains('Nagpur')));
      expect(listing.latitude, 18.52);
      expect(listing.longitude, 73.86);
      expect(listing.distanceKm, 12.5);
    },
  );

  test('detail listing never falls back to owner or exact address', () {
    final service = ServiceModel.fromMap('service-missing-location', {
      'ownerSnapshot': {'city': 'Nagpur', 'state': 'Maharashtra'},
      'location': {
        'displayAddress': 'Private exact address, Pune',
        'latitude': 18.5204,
        'longitude': 73.8567,
      },
    });

    final listing = service.toProfileListing();

    expect(listing.publicLocationLabel, 'Location unavailable');
    expect(listing.location, isEmpty);
    expect(listing.location, isNot(contains('Nagpur')));
    expect(listing.location, isNot(contains('Private exact address')));
    expect(listing.latitude, 18.5204);
    expect(listing.longitude, 73.8567);
  });
}
