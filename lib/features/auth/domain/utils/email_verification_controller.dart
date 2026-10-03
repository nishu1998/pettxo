enum EmailVerificationRefreshResult {
  pending,
  verified,
  reauthenticationRequired,
}

class EmailVerificationIdentityChangedException implements Exception {
  const EmailVerificationIdentityChangedException();

  @override
  String toString() =>
      'Pettxo detected an unexpected account change. Please sign in again.';
}

class EmailVerificationController {
  final Future<void> Function() reloadCurrentUser;
  final Future<void> Function() refreshIdToken;
  final String Function() currentUid;
  final bool Function() isEmailVerified;
  final Future<void> Function() syncTrustedAuthIdentity;
  final bool Function(Object error) isSessionInvalidError;
  final String expectedUid;

  const EmailVerificationController({
    required this.reloadCurrentUser,
    required this.refreshIdToken,
    required this.currentUid,
    required this.isEmailVerified,
    required this.syncTrustedAuthIdentity,
    required this.isSessionInvalidError,
    required this.expectedUid,
  });

  Future<EmailVerificationRefreshResult> refreshVerificationStatus() async {
    try {
      await reloadCurrentUser();
    } catch (error) {
      if (isSessionInvalidError(error)) {
        return EmailVerificationRefreshResult.reauthenticationRequired;
      }
      rethrow;
    }

    final uidAfterReload = currentUid().trim();
    if (uidAfterReload.isEmpty) {
      return EmailVerificationRefreshResult.reauthenticationRequired;
    }
    if (uidAfterReload != expectedUid.trim()) {
      throw const EmailVerificationIdentityChangedException();
    }
    if (!isEmailVerified()) {
      return EmailVerificationRefreshResult.pending;
    }

    try {
      await refreshIdToken();
      final uidAfterTokenRefresh = currentUid().trim();
      if (uidAfterTokenRefresh.isEmpty) {
        return EmailVerificationRefreshResult.reauthenticationRequired;
      }
      if (uidAfterTokenRefresh != expectedUid.trim()) {
        throw const EmailVerificationIdentityChangedException();
      }
      await syncTrustedAuthIdentity();
    } catch (error) {
      if (isSessionInvalidError(error)) {
        return EmailVerificationRefreshResult.reauthenticationRequired;
      }
      rethrow;
    }

    return EmailVerificationRefreshResult.verified;
  }
}
