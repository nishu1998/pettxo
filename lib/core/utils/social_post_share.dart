import '../../features/social/domain/models/social_post_model.dart';

const String _pettxoPostShareHost = 'pettxo.com';

String buildSocialPostShareUrl(String postId) {
  final normalizedPostId = postId.trim();
  return Uri(
    scheme: 'https',
    host: _pettxoPostShareHost,
    pathSegments: ['post', normalizedPostId],
  ).toString();
}

String buildSocialPostShareText(SocialPostModel post) {
  final sections = <String>['🐾 Check out this post on Pettxo'];
  final detailLines = <String>[
    if (post.authorDisplayName.trim().isNotEmpty) post.authorDisplayName.trim(),
    if (post.caption.trim().isNotEmpty) post.caption.trim(),
  ];
  if (detailLines.isNotEmpty) {
    sections.add(detailLines.join('\n'));
  }
  sections.add(buildSocialPostShareUrl(post.id));
  return sections.join('\n\n');
}

String? tryParseSocialPostIdFromUri(Uri uri) {
  final host = uri.host.trim().toLowerCase();
  if (host != _pettxoPostShareHost && host != 'www.$_pettxoPostShareHost') {
    return null;
  }
  if (uri.scheme.trim().toLowerCase() != 'https') {
    return null;
  }
  final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
  if (segments.length != 2) {
    return null;
  }
  final values = segments.toList(growable: false);
  if (values.first != 'post') return null;
  final postId = values[1].trim();
  return postId.isEmpty ? null : postId;
}
