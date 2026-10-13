import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/explore/data/explore_location_repository.dart';
import 'package:pettexo/features/explore/domain/models/explore_location_snapshot.dart';
import 'package:pettexo/features/social/application/post_location_publish_resolver.dart';

void main() {
  const resolver = PostLocationPublishResolver();

  test('opted-out post never requests a location', () async {
    var captureCount = 0;
    final result = await resolver.resolve(
      includeLocation: false,
      capture: () async {
        captureCount += 1;
        return const ExploreLocationState(
          availability: ExploreLocationAvailability.ready,
        );
      },
      chooseAfterFailure: (_) async => PostLocationFailureChoice.cancel,
    );

    expect(result.shouldPublish, isTrue);
    expect(result.includeLocation, isFalse);
    expect(captureCount, 0);
  });

  test('valid fresh location is kept for the publish operation', () async {
    final location = ExploreLocationSnapshot(
      latitude: 28.61,
      longitude: 77.20,
      city: 'New Delhi',
      state: 'Delhi',
      country: 'India',
      geohash3: 'ttn',
      geohash4: 'ttnf',
      geohash5: 'ttnfv',
      updatedAt: DateTime(2026),
    );
    final result = await resolver.resolve(
      includeLocation: true,
      capture: () async => ExploreLocationState(
        availability: ExploreLocationAvailability.ready,
        snapshot: location,
      ),
      chooseAfterFailure: (_) async => PostLocationFailureChoice.cancel,
    );

    expect(result.shouldPublish, isTrue);
    expect(result.includeLocation, isTrue);
    expect(result.location, same(location));
  });

  test('failed capture requires explicit continue without location', () async {
    final result = await resolver.resolve(
      includeLocation: true,
      capture: () async => const ExploreLocationState(
        availability: ExploreLocationAvailability.permissionDenied,
      ),
      chooseAfterFailure: (_) async =>
          PostLocationFailureChoice.continueWithoutLocation,
    );

    expect(result.shouldPublish, isTrue);
    expect(result.includeLocation, isFalse);
    expect(result.location, isNull);
  });

  test('retry captures again while cancel keeps the editor open', () async {
    var captureCount = 0;
    var choiceCount = 0;
    final result = await resolver.resolve(
      includeLocation: true,
      capture: () async {
        captureCount += 1;
        return const ExploreLocationState(
          availability: ExploreLocationAvailability.unavailable,
        );
      },
      chooseAfterFailure: (_) async {
        choiceCount += 1;
        return choiceCount == 1
            ? PostLocationFailureChoice.retry
            : PostLocationFailureChoice.cancel;
      },
    );

    expect(result.shouldPublish, isFalse);
    expect(captureCount, 2);
  });
}
