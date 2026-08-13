import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/auth/domain/utils/phone_login_eligibility_utils.dart';

void main() {
  group('parsePhoneLoginEligibilityResponse', () {
    test('parses active response correctly', () {
      final parsed = parsePhoneLoginEligibilityResponse(const {
        'exists': true,
        'canLogin': true,
        'reason': 'active',
      });

      expect(parsed.exists, isTrue);
      expect(parsed.canLogin, isTrue);
      expect(parsed.reason, PhoneLoginEligibilityReason.active);
      expect(parsed.isMalformed, isFalse);
    });

    test('parses not_found response correctly', () {
      final parsed = parsePhoneLoginEligibilityResponse(const {
        'exists': false,
        'canLogin': false,
        'reason': 'not_found',
      });

      expect(parsed.exists, isFalse);
      expect(parsed.canLogin, isFalse);
      expect(parsed.reason, PhoneLoginEligibilityReason.notFound);
      expect(parsed.isMalformed, isFalse);
    });

    test('treats malformed response as technical failure', () {
      final parsed = parsePhoneLoginEligibilityResponse(const {
        'exists': 'false',
        'canLogin': false,
        'reason': 'blocked',
      });

      expect(parsed.isMalformed, isTrue);
      expect(parsed.reason, PhoneLoginEligibilityReason.technicalFailure);
    });
  });

  group('phoneLoginDecisionForParsedResult', () {
    test('starts OTP for active loginable account', () {
      final decision = phoneLoginDecisionForParsedResult(
        const ParsedPhoneLoginEligibility(
          exists: true,
          canLogin: true,
          reason: PhoneLoginEligibilityReason.active,
        ),
      );

      expect(decision, PhoneLoginEligibilityDecision.startOtp);
    });

    test('starts OTP for incomplete signup that can continue onboarding', () {
      final parsed = const ParsedPhoneLoginEligibility(
        exists: true,
        canLogin: true,
        reason: PhoneLoginEligibilityReason.incompleteSignup,
      );

      expect(
        phoneLoginDecisionForParsedResult(parsed),
        PhoneLoginEligibilityDecision.startOtp,
      );
      expect(
        phoneLoginMessageForParsedResult(parsed),
        'Your account setup is incomplete. Continue to finish onboarding.',
      );
    });

    test('shows signup-first message for not_found', () {
      final parsed = const ParsedPhoneLoginEligibility(
        exists: false,
        canLogin: false,
        reason: PhoneLoginEligibilityReason.notFound,
      );

      expect(
        phoneLoginDecisionForParsedResult(parsed),
        PhoneLoginEligibilityDecision.showNotFound,
      );
      expect(
        phoneLoginMessageForParsedResult(parsed),
        'No account exists with this phone number. Please sign up first.',
      );
    });

    test('shows technical retry message for malformed response', () {
      final parsed = const ParsedPhoneLoginEligibility(
        exists: false,
        canLogin: false,
        reason: PhoneLoginEligibilityReason.technicalFailure,
        isMalformed: true,
      );

      expect(
        phoneLoginDecisionForParsedResult(parsed),
        PhoneLoginEligibilityDecision.showNetworkError,
      );
      expect(
        phoneLoginMessageForParsedResult(parsed),
        'Unable to verify this phone number right now. Please try again.',
      );
    });
  });
}
