import '../../../../core/constants/validators.dart';

String? validateAccountSecurityPassword(String password) {
  return Validators.validatePassword(password.trim());
}

String? validatePasswordConfirmation({
  required String password,
  required String confirmation,
}) {
  if (confirmation.trim().isEmpty) {
    return 'Please confirm your password';
  }
  if (password != confirmation) {
    return 'Passwords do not match';
  }
  return null;
}
