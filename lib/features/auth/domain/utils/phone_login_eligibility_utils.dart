enum PhoneLoginEligibilityReason {
  active,
  notFound,
  incompleteSignup,
  blocked,
  accountRecoveryRequired,
  technicalFailure,
}

enum PhoneLoginEligibilityDecision {
  startOtp,
  showNotFound,
  showBlocked,
  showRecovery,
  showNetworkError,
}

class ParsedPhoneLoginEligibility {
  final bool exists;
  final bool canLogin;
  final PhoneLoginEligibilityReason reason;
  final bool isMalformed;

  const ParsedPhoneLoginEligibility({
    required this.exists,
    required this.canLogin,
    required this.reason,
    this.isMalformed = false,
  });
}

String maskPhoneNumberForLogs(String phoneNumber) {
  final trimmed = phoneNumber.trim();
  if (trimmed.isEmpty) return '';
  final prefix = trimmed.startsWith('+91') ? '+91' : '+';
  final digits = trimmed.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 4) return '$prefix******';
  final suffix = digits.substring(digits.length - 4);
  return '$prefix******$suffix';
}

PhoneLoginEligibilityReason? phoneLoginReasonFromWire(String? reason) {
  switch ((reason ?? '').trim()) {
    case 'active':
      return PhoneLoginEligibilityReason.active;
    case 'not_found':
      return PhoneLoginEligibilityReason.notFound;
    case 'incomplete_signup':
      return PhoneLoginEligibilityReason.incompleteSignup;
    case 'blocked':
      return PhoneLoginEligibilityReason.blocked;
    case 'account_recovery_required':
      return PhoneLoginEligibilityReason.accountRecoveryRequired;
    default:
      return null;
  }
}

String phoneLoginReasonToWire(PhoneLoginEligibilityReason reason) {
  switch (reason) {
    case PhoneLoginEligibilityReason.active:
      return 'active';
    case PhoneLoginEligibilityReason.notFound:
      return 'not_found';
    case PhoneLoginEligibilityReason.incompleteSignup:
      return 'incomplete_signup';
    case PhoneLoginEligibilityReason.blocked:
      return 'blocked';
    case PhoneLoginEligibilityReason.accountRecoveryRequired:
      return 'account_recovery_required';
    case PhoneLoginEligibilityReason.technicalFailure:
      return 'technical_failure';
  }
}

ParsedPhoneLoginEligibility parsePhoneLoginEligibilityResponse(Object? data) {
  if (data is! Map) {
    return const ParsedPhoneLoginEligibility(
      exists: false,
      canLogin: false,
      reason: PhoneLoginEligibilityReason.technicalFailure,
      isMalformed: true,
    );
  }

  final exists = data['exists'];
  final canLogin = data['canLogin'];
  final reason = phoneLoginReasonFromWire(data['reason'] as String?);
  if (exists is! bool || canLogin is! bool || reason == null) {
    return const ParsedPhoneLoginEligibility(
      exists: false,
      canLogin: false,
      reason: PhoneLoginEligibilityReason.technicalFailure,
      isMalformed: true,
    );
  }

  return ParsedPhoneLoginEligibility(
    exists: exists,
    canLogin: canLogin,
    reason: reason,
  );
}

PhoneLoginEligibilityDecision phoneLoginDecisionForParsedResult(
  ParsedPhoneLoginEligibility result,
) {
  if (result.isMalformed ||
      result.reason == PhoneLoginEligibilityReason.technicalFailure) {
    return PhoneLoginEligibilityDecision.showNetworkError;
  }
  if (result.canLogin && result.reason == PhoneLoginEligibilityReason.active) {
    return PhoneLoginEligibilityDecision.startOtp;
  }
  if (result.canLogin &&
      result.reason == PhoneLoginEligibilityReason.incompleteSignup) {
    return PhoneLoginEligibilityDecision.startOtp;
  }
  switch (result.reason) {
    case PhoneLoginEligibilityReason.notFound:
      return PhoneLoginEligibilityDecision.showNotFound;
    case PhoneLoginEligibilityReason.blocked:
      return PhoneLoginEligibilityDecision.showBlocked;
    case PhoneLoginEligibilityReason.incompleteSignup:
      return PhoneLoginEligibilityDecision.startOtp;
    case PhoneLoginEligibilityReason.accountRecoveryRequired:
      return PhoneLoginEligibilityDecision.showRecovery;
    case PhoneLoginEligibilityReason.active:
      return PhoneLoginEligibilityDecision.showNetworkError;
    case PhoneLoginEligibilityReason.technicalFailure:
      return PhoneLoginEligibilityDecision.showNetworkError;
  }
}

String phoneLoginMessageForDecision(PhoneLoginEligibilityDecision decision) {
  switch (decision) {
    case PhoneLoginEligibilityDecision.startOtp:
      return '';
    case PhoneLoginEligibilityDecision.showNotFound:
      return 'No account exists with this phone number. Please sign up first.';
    case PhoneLoginEligibilityDecision.showBlocked:
      return 'This account cannot sign in right now.';
    case PhoneLoginEligibilityDecision.showRecovery:
      return 'This account is in recovery mode. Complete account recovery to continue.';
    case PhoneLoginEligibilityDecision.showNetworkError:
      return 'Unable to verify this phone number right now. Please try again.';
  }
}

String phoneLoginMessageForParsedResult(ParsedPhoneLoginEligibility result) {
  if (result.isMalformed ||
      result.reason == PhoneLoginEligibilityReason.technicalFailure) {
    return 'Unable to verify this phone number right now. Please try again.';
  }
  switch (result.reason) {
    case PhoneLoginEligibilityReason.active:
      return '';
    case PhoneLoginEligibilityReason.notFound:
      return 'No account exists with this phone number. Please sign up first.';
    case PhoneLoginEligibilityReason.incompleteSignup:
      return 'Your account setup is incomplete. Continue to finish onboarding.';
    case PhoneLoginEligibilityReason.blocked:
      return 'This account cannot sign in right now.';
    case PhoneLoginEligibilityReason.accountRecoveryRequired:
      return 'This account is in recovery mode. Complete account recovery to continue.';
    case PhoneLoginEligibilityReason.technicalFailure:
      return 'Unable to verify this phone number right now. Please try again.';
  }
}
