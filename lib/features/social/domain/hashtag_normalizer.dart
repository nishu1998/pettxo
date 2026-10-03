const int maxHashtagsPerPost = 5;
const int maxHashtagLength = 30;

String normalizeHashtag(String input) {
  final trimmed = input.trim();
  final withoutPrefix = trimmed.startsWith('#')
      ? trimmed.substring(1)
      : trimmed;
  final normalized = withoutPrefix.toLowerCase();
  if (normalized.isEmpty || normalized.contains(RegExp(r'\s'))) {
    return '';
  }
  return normalized;
}

bool isValidCanonicalHashtag(String tag) {
  return tag.isNotEmpty &&
      tag.length <= maxHashtagLength &&
      RegExp(r'^[a-z0-9_]+$').hasMatch(tag);
}

List<String> normalizeHashtags(Iterable<String> hashtags) {
  return hashtags
      .map(normalizeHashtag)
      .where(isValidCanonicalHashtag)
      .toSet()
      .toList(growable: false);
}

List<String> validatePostHashtags(Iterable<String> hashtags) {
  final source = hashtags.toList(growable: false);
  if (source.length > maxHashtagsPerPost) {
    throw const FormatException('You can add up to 5 hashtags.');
  }
  final normalized = <String>[];
  for (final input in source) {
    final tag = normalizeHashtag(input);
    if (!isValidCanonicalHashtag(tag)) {
      throw const FormatException(
        'Each hashtag must use letters, numbers, or underscores and contain no more than 30 characters.',
      );
    }
    if (!normalized.contains(tag)) normalized.add(tag);
  }
  return List<String>.unmodifiable(normalized);
}
