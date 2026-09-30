import '../models/password_reset_request_result.dart';
import 'password_reset_utils.dart';

typedef PasswordResetRequester = Future<void> Function(String normalizedEmail);
typedef PasswordResetErrorMapper =
    PasswordResetRequestResult Function(
      Object error,
      StackTrace stackTrace,
      String normalizedEmail,
    );

Future<PasswordResetRequestResult> runPasswordResetRequestFlow({
  required String email,
  required PasswordResetRequester requestReset,
  required PasswordResetErrorMapper mapError,
}) async {
  final normalizedEmail = normalizePasswordResetEmail(email);
  final validationError = validatePasswordResetEmail(normalizedEmail);
  if (validationError != null) {
    return PasswordResetRequestResult(
      status: PasswordResetRequestStatus.invalidEmail,
      normalizedEmail: normalizedEmail,
      message: validationError,
    );
  }

  try {
    await requestReset(normalizedEmail);
    return PasswordResetRequestResult(
      status: PasswordResetRequestStatus.sent,
      normalizedEmail: normalizedEmail,
      message:
          "If an account exists for that email, we've sent password reset instructions.",
    );
  } catch (error, stackTrace) {
    return mapError(error, stackTrace, normalizedEmail);
  }
}
