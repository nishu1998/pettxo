String normalizeSupportContactNumber(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';

  final compact = trimmed.replaceAll(RegExp(r'[\s\-()]'), '');
  if (compact.startsWith('+')) {
    return '+${compact.substring(1).replaceAll(RegExp(r'\D'), '')}';
  }

  final digitsOnly = compact.replaceAll(RegExp(r'\D'), '');
  if (digitsOnly.length == 10) {
    return '+91$digitsOnly';
  }
  if (digitsOnly.length == 11 && digitsOnly.startsWith('0')) {
    return '+91${digitsOnly.substring(1)}';
  }
  if (digitsOnly.length == 12 && digitsOnly.startsWith('91')) {
    return '+$digitsOnly';
  }
  return compact;
}

String? validateSupportContactNumber(String value) {
  final normalized = normalizeSupportContactNumber(value);
  if (normalized.isEmpty) {
    return 'Contact number is required.';
  }
  if (!RegExp(r'^\+\d{10,15}$').hasMatch(normalized)) {
    return 'Enter a valid contact number.';
  }
  return null;
}

String? supportPhoneFieldInitialNumber(String phoneNumber) {
  final trimmed = phoneNumber.trim();
  if (trimmed.startsWith('+91') && trimmed.length > 3) {
    return trimmed.substring(3);
  }
  if (trimmed.startsWith('+') && trimmed.length > 1) {
    return trimmed.substring(1);
  }
  return trimmed.isEmpty ? null : trimmed;
}
