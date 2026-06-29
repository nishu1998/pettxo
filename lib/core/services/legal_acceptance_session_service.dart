class LegalAcceptanceSessionService {
  LegalAcceptanceSessionService._();

  static final LegalAcceptanceSessionService instance =
      LegalAcceptanceSessionService._();

  bool _signupConsentAccepted = false;

  bool get hasPendingSignupConsent => _signupConsentAccepted;

  void markSignupConsentAccepted() {
    _signupConsentAccepted = true;
  }

  void clearSignupConsent() {
    _signupConsentAccepted = false;
  }
}
