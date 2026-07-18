class UsernameValidationResult {
  final String normalized;
  final String? error;

  const UsernameValidationResult({
    required this.normalized,
    required this.error,
  });

  bool get isValid => error == null;
}

const int kUsernameMinLength = 3;
const int kUsernameMaxLength = 20;

final RegExp kUsernamePattern = RegExp(r'^[a-z0-9_.]{3,20}$');
const Set<String> kReservedUsernames = {
  'admin',
  'administrator',
  'api',
  'auth',
  'help',
  'me',
  'notifications',
  'pettxo',
  'root',
  'security',
  'settings',
  'signin',
  'signup',
  'support',
  'system',
  'user',
  'username',
};

String normalizeUsername(String value) {
  return value.trim().replaceAll('@', '').toLowerCase();
}

String? validateNormalizedUsername(String normalized) {
  if (normalized.isEmpty) {
    return 'Username is required';
  }

  if (!kUsernamePattern.hasMatch(normalized)) {
    return 'Use 3-20 lowercase letters, numbers, dots, or underscores';
  }

  if (normalized.startsWith('.') || normalized.endsWith('.')) {
    return 'Username cannot start or end with a dot';
  }

  if (normalized.contains('..')) {
    return 'Username cannot contain consecutive dots';
  }

  if (kReservedUsernames.contains(normalized)) {
    return 'This username is reserved';
  }

  return null;
}

UsernameValidationResult normalizeAndValidateUsername(String value) {
  final normalized = normalizeUsername(value);
  return UsernameValidationResult(
    normalized: normalized,
    error: validateNormalizedUsername(normalized),
  );
}
