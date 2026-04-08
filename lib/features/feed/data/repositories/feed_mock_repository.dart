import '../../domain/models/feed_post.dart';

class FeedMockRepository {
  const FeedMockRepository();

  List<FeedPost> getPosts() {
    return const [
      FeedPost(
        displayName: "Sarah's Pet Care",
        username: "@sarahpetcare",
        roleLabel: "Provider",
        mediaUrl:
            "https://images.unsplash.com/photo-1517849845537-4d257902454a?auto=format&fit=crop&w=1200&q=80",
        caption:
            "Fresh grooming session with this cutie. Book your appointment today.",
        likesCount: 124,
        commentsCount: 18,
        isServicePost: true,
        ctaLabel: "View Service",
      ),
      FeedPost(
        displayName: "Max & Charlie",
        username: "@maxandcharlie",
        roleLabel: "Pet Parent",
        mediaUrl:
            "https://images.unsplash.com/photo-1548199973-03cce0bbc87b?auto=format&fit=crop&w=1200&q=80",
        caption:
            "Morning park run, extra zoomies, and a lot of mud. Worth it every time.",
        likesCount: 296,
        commentsCount: 32,
        isServicePost: false,
      ),
      FeedPost(
        displayName: "Paws & Whiskers Club",
        username: "@pawswhiskersclub",
        roleLabel: "Pet Lover",
        mediaUrl:
            "https://images.unsplash.com/photo-1519052537078-e6302a4968d4?auto=format&fit=crop&w=1200&q=80",
        caption:
            "Weekend adoption meetup was full of happy tails, warm cuddles, and so much love.",
        likesCount: 412,
        commentsCount: 47,
        isServicePost: false,
      ),
    ];
  }
}
