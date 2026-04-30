class RestrictionFlag {
  final bool isBanned;
  final String reason;

  const RestrictionFlag({
    required this.isBanned,
    required this.reason,
  });

  factory RestrictionFlag.fromMap(Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    return RestrictionFlag(
      isBanned: source['isBanned'] == true,
      reason: (source['reason'] as String? ?? '').trim(),
    );
  }

  static const empty = RestrictionFlag(isBanned: false, reason: '');
}

class UserRestrictionState {
  static const String socialBanMessage = 'Your social features are restricted.';
  static const String bookingBanMessage =
      'Your booking features are restricted. Contact support.';
  static const String hardBanMessage = 'Your account has been disabled.';

  final String accountStatus;
  final RestrictionFlag social;
  final RestrictionFlag booking;
  final RestrictionFlag hard;

  const UserRestrictionState({
    required this.accountStatus,
    required this.social,
    required this.booking,
    required this.hard,
  });

  factory UserRestrictionState.fromMap(Map<String, dynamic>? data) {
    final source = data ?? const <String, dynamic>{};
    final restrictions =
        source['restrictions'] as Map<String, dynamic>? ??
        const <String, dynamic>{};

    return UserRestrictionState(
      accountStatus: (source['accountStatus'] as String? ?? 'active').trim(),
      social: RestrictionFlag.fromMap(
        restrictions['social'] as Map<String, dynamic>?,
      ),
      booking: RestrictionFlag.fromMap(
        restrictions['booking'] as Map<String, dynamic>?,
      ),
      hard: RestrictionFlag.fromMap(
        restrictions['hard'] as Map<String, dynamic>?,
      ),
    );
  }

  static const unrestricted = UserRestrictionState(
    accountStatus: 'active',
    social: RestrictionFlag.empty,
    booking: RestrictionFlag.empty,
    hard: RestrictionFlag.empty,
  );

  bool get isHardBanned => accountStatus == 'hardBanned' || hard.isBanned;

  bool get canUseSocialFeatures => !isHardBanned && !social.isBanned;

  bool get canUseBookingFeatures => !isHardBanned && !booking.isBanned;
}
