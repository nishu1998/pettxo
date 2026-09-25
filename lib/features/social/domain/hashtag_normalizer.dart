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
      tag.length <= 30 &&
      RegExp(r'^[a-z0-9_]+$').hasMatch(tag);
}

List<String> normalizeHashtags(Iterable<String> hashtags) {
  return hashtags
      .map(normalizeHashtag)
      .where(isValidCanonicalHashtag)
      .toSet()
      .toList(growable: false);
}
