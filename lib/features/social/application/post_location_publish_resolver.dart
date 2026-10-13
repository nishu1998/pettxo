import '../../explore/data/explore_location_repository.dart';
import '../../explore/domain/models/explore_location_snapshot.dart';

enum PostLocationFailureChoice { retry, continueWithoutLocation, cancel }

class PostLocationPublishResolution {
  const PostLocationPublishResolution._({
    required this.shouldPublish,
    required this.includeLocation,
    this.location,
  });

  const PostLocationPublishResolution.cancelled()
    : this._(shouldPublish: false, includeLocation: false);

  const PostLocationPublishResolution.withoutLocation()
    : this._(shouldPublish: true, includeLocation: false);

  PostLocationPublishResolution.withLocation(ExploreLocationSnapshot location)
    : this._(shouldPublish: true, includeLocation: true, location: location);

  final bool shouldPublish;
  final bool includeLocation;
  final ExploreLocationSnapshot? location;
}

typedef PostLocationCapture = Future<ExploreLocationState> Function();
typedef PostLocationFailureChoiceCallback =
    Future<PostLocationFailureChoice> Function(ExploreLocationState state);

class PostLocationPublishResolver {
  const PostLocationPublishResolver();

  Future<PostLocationPublishResolution> resolve({
    required bool includeLocation,
    required PostLocationCapture capture,
    required PostLocationFailureChoiceCallback chooseAfterFailure,
  }) async {
    if (!includeLocation) {
      return const PostLocationPublishResolution.withoutLocation();
    }

    while (true) {
      final state = await capture();
      if (state.snapshot.hasCoordinates) {
        return PostLocationPublishResolution.withLocation(state.snapshot);
      }

      final choice = await chooseAfterFailure(state);
      switch (choice) {
        case PostLocationFailureChoice.retry:
          continue;
        case PostLocationFailureChoice.continueWithoutLocation:
          return const PostLocationPublishResolution.withoutLocation();
        case PostLocationFailureChoice.cancel:
          return const PostLocationPublishResolution.cancelled();
      }
    }
  }
}
