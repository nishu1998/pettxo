import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/constants/signup_terms_communications.dart';

void main() {
  test('signup disclosure explicitly states marketing choice and controls', () {
    expect(signupTermsCommunicationsPolicyVersion, isNotEmpty);
    expect(signupMarketingCommunicationsDisclosure, contains('offers'));
    expect(
      signupMarketingCommunicationsDisclosure,
      contains('product updates'),
    );
    expect(
      signupMarketingCommunicationsDisclosure,
      contains('promotional emails'),
    );
    expect(signupMarketingCommunicationsDisclosure, contains('unsubscribe'));
    expect(signupMarketingCommunicationsDisclosure, contains('Settings'));
  });

  test('email and phone signup use the shortened consent wording', () {
    expect(
      signupConsentDisplayText,
      "I agree to Pettxo's Terms of Service, Privacy Policy and Community Guidelines, including promotional emails (opt out anytime in Settings).",
    );
  });
}
