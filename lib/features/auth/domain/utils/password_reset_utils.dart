String normalizePasswordResetEmail(String email) {
  return email.trim().toLowerCase();
}

String? validatePasswordResetEmail(String email) {
  final normalized = normalizePasswordResetEmail(email);
  if (normalized.isEmpty) {
    return 'Email is required.';
  }
  final emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  if (!emailPattern.hasMatch(normalized)) {
    return 'Enter a valid email address.';
  }
  return null;
}
