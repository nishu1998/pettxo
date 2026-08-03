String nearbyLoadErrorMessage(Object error) {
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  if (message.isEmpty) {
    return 'We couldn’t load nearby posts. Please try again.';
  }

  final normalized = message.toLowerCase();
  if (normalized.contains('type ') ||
      normalized.contains('is not a subtype') ||
      normalized.contains('_map<object?, object?>') ||
      normalized.contains('timestamp')) {
    return 'We couldn’t load nearby posts. Please try again.';
  }

  return message;
}
