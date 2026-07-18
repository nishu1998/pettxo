enum PasswordResetRequestStatus {
  sent,
  accountNotFound,
  phoneOnlyAccount,
  accountPendingDeletion,
  accountDisabled,
  invalidEmail,
  rateLimited,
  networkError,
  unknownError,
}

class PasswordResetRequestResult {
  final PasswordResetRequestStatus status;
  final String normalizedEmail;
  final String message;

  const PasswordResetRequestResult({
    required this.status,
    required this.normalizedEmail,
    required this.message,
  });

  bool get isSuccess => status == PasswordResetRequestStatus.sent;
}
