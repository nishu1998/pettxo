import 'explore_location_snapshot.dart';

class ExploreFeedViewerContext {
  final String currentUserId;
  final String city;
  final String state;
  final ExploreLocationSnapshot locationSnapshot;
  final Set<String> followingIds;
  final Set<String> blockedUserIds;
  final Set<String> mutedUserIds;

  const ExploreFeedViewerContext({
    required this.currentUserId,
    required this.city,
    required this.state,
    required this.locationSnapshot,
    required this.followingIds,
    required this.blockedUserIds,
    required this.mutedUserIds,
  });

  static const empty = ExploreFeedViewerContext(
    currentUserId: '',
    city: '',
    state: '',
    locationSnapshot: ExploreLocationSnapshot.empty,
    followingIds: <String>{},
    blockedUserIds: <String>{},
    mutedUserIds: <String>{},
  );

  String get normalizedCity => city.trim().toLowerCase();
  String get normalizedState => state.trim().toLowerCase();

  ExploreFeedViewerContext copyWith({
    String? currentUserId,
    String? city,
    String? state,
    ExploreLocationSnapshot? locationSnapshot,
    Set<String>? followingIds,
    Set<String>? blockedUserIds,
    Set<String>? mutedUserIds,
  }) {
    return ExploreFeedViewerContext(
      currentUserId: currentUserId ?? this.currentUserId,
      city: city ?? this.city,
      state: state ?? this.state,
      locationSnapshot: locationSnapshot ?? this.locationSnapshot,
      followingIds: followingIds ?? this.followingIds,
      blockedUserIds: blockedUserIds ?? this.blockedUserIds,
      mutedUserIds: mutedUserIds ?? this.mutedUserIds,
    );
  }
}
