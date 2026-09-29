enum UsernameAvailabilityStatus {
  available,
  owned,
  taken,
  reserved,
  staleReservation,
  invalid,
}

class UsernameAvailabilityResult {
  const UsernameAvailabilityResult({
    required this.username,
    required this.status,
  });

  final String username;
  final UsernameAvailabilityStatus status;

  bool get isAvailable =>
      status == UsernameAvailabilityStatus.available ||
      status == UsernameAvailabilityStatus.owned;

  factory UsernameAvailabilityResult.fromMap(Map<String, dynamic> data) {
    final rawStatus = (data['status'] as String? ?? '').trim();
    final status = switch (rawStatus) {
      'available' => UsernameAvailabilityStatus.available,
      'owned' => UsernameAvailabilityStatus.owned,
      'taken' => UsernameAvailabilityStatus.taken,
      'reserved' => UsernameAvailabilityStatus.reserved,
      'staleReservation' => UsernameAvailabilityStatus.staleReservation,
      'invalid' => UsernameAvailabilityStatus.invalid,
      _ => throw const FormatException(
        'Invalid username availability response.',
      ),
    };
    return UsernameAvailabilityResult(
      username: (data['username'] as String? ?? '').trim(),
      status: status,
    );
  }
}
