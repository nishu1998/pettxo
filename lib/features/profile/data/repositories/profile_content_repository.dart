import '../../../feed/data/repositories/feed_mock_repository.dart';
import '../../../feed/domain/models/feed_post.dart';
import '../../domain/models/user_profile.dart';

class ProfileContentRepository {
  const ProfileContentRepository();

  List<FeedPost> getPostsForProfile(UserProfile profile) {
    final username = profile.displayUsername.toLowerCase();
    if (username.isEmpty) return const [];

    return const FeedMockRepository().getPosts().where((post) {
      return post.username.toLowerCase() == username;
    }).toList();
  }
}
