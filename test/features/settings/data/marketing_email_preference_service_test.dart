import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/settings/data/services/marketing_email_preference_service.dart';

void main() {
  test('marketing preference is enabled only by an explicit true value', () {
    expect(
      parseMarketingEmailPreference({'marketingEmailEnabled': true}),
      isTrue,
    );
    expect(
      parseMarketingEmailPreference({'marketingEmailEnabled': false}),
      isFalse,
    );
    expect(parseMarketingEmailPreference({}), isFalse);
    expect(
      parseMarketingEmailPreference({'marketingEmailEnabled': 'true'}),
      isFalse,
    );
  });
}
