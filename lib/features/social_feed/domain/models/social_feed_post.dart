class SocialFeedPost {
  final String displayName;
  final String username;
  final String roleLabel;
  final String mediaUrl;
  final String caption;
  final int likesCount;
  final int commentsCount;
  final bool isServicePost;
  final String? ctaLabel;

  const SocialFeedPost({
    required this.displayName,
    required this.username,
    required this.roleLabel,
    required this.mediaUrl,
    required this.caption,
    required this.likesCount,
    required this.commentsCount,
    required this.isServicePost,
    this.ctaLabel,
  });
}
