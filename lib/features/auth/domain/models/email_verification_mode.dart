enum EmailVerificationMode { blockingOnboarding, nonBlockingLinkedEmail }

extension EmailVerificationModeX on EmailVerificationMode {
  bool get blocksAppAccess => this == EmailVerificationMode.blockingOnboarding;

  bool requestsEmailChangeVerification({
    required String currentEmail,
    required String expectedEmail,
  }) {
    final normalizedCurrent = currentEmail.trim().toLowerCase();
    final normalizedExpected = expectedEmail.trim().toLowerCase();
    return this == EmailVerificationMode.nonBlockingLinkedEmail &&
        normalizedExpected.isNotEmpty &&
        normalizedExpected != normalizedCurrent;
  }

  String get title {
    return switch (this) {
      EmailVerificationMode.blockingOnboarding => 'Verify Your Email',
      EmailVerificationMode.nonBlockingLinkedEmail => 'Verify Linked Email',
    };
  }

  String subtitle(String maskedEmail) {
    return switch (this) {
      EmailVerificationMode.blockingOnboarding =>
        'Open the verification link we sent to $maskedEmail before continuing.',
      EmailVerificationMode.nonBlockingLinkedEmail =>
        'We sent a verification link to $maskedEmail. Your phone sign-in still works while this email stays pending.',
    };
  }
}
