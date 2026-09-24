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
}
