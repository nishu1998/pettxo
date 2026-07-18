import '../models/password_reset_request_result.dart';
import 'password_reset_utils.dart';

typedef PasswordResetApproval = Future<void> Function(String normalizedEmail);
typedef PasswordResetSender = Future<void> Function(String normalizedEmail);
typedef PasswordResetErrorMapper =
    PasswordResetRequestResult Function(
      Object error,
      StackTrace stackTrace,
      String normalizedEmail,
    );

Future<PasswordResetRequestResult> runPasswordResetRequestFlow({
  required String email,
  required PasswordResetApproval approveRequest,
  required PasswordResetSender sendResetEmail,
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
    await approveRequest(normalizedEmail);
    await sendResetEmail(normalizedEmail);
    return PasswordResetRequestResult(
      status: PasswordResetRequestStatus.sent,
      normalizedEmail: normalizedEmail,
      message: 'Check your inbox and follow the link to create a new password.',
    );
  } catch (error, stackTrace) {
    return mapError(error, stackTrace, normalizedEmail);
  }
}
