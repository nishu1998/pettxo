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
}
