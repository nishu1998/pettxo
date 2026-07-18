class EmailVerificationController {
  final Future<void> Function() reloadCurrentUser;
  final bool Function() isEmailVerified;
  final Future<void> Function() syncTrustedAuthIdentity;

  const EmailVerificationController({
    required this.reloadCurrentUser,
    required this.isEmailVerified,
    required this.syncTrustedAuthIdentity,
  });

  Future<bool> refreshVerificationStatus() async {
    await reloadCurrentUser();
    if (!isEmailVerified()) {
      return false;
    }
    await syncTrustedAuthIdentity();
    return true;
  }
}
