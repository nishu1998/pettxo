import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/settings/presentation/screens/legal_policies_screen.dart';

void main() {
  test('catalog contains the approved policy copy in one source of truth', () {
    expect(LegalPoliciesCatalog.documents, hasLength(5));

    expect(
      LegalPoliciesCatalog.cancellationPolicy.items,
      containsAllInOrder([
        isA<LegalPolicyItem>().having(
          (item) => item.text,
          'text',
          'You can cancel a booking request for free at any time before you pay. Nothing is charged until payment.',
        ),
        isA<LegalPolicyItem>()
            .having(
              (item) => item.text,
              'text',
              'After payment, your refund depends on how much time is left before the service starts:',
            )
            .having((item) => item.details, 'details', const [
              'More than 24 hours before: 95% back',
              '12 to 24 hours before: 75% back',
              '6 to 12 hours before: 50% back',
              '2 to 6 hours before: 25% back',
              'Less than 2 hours before: no refund',
            ]),
        isA<LegalPolicyItem>().having(
          (item) => item.text,
          'text',
          "Once the provider enters your OTP, the service has started and the booking can't be cancelled.",
        ),
        isA<LegalPolicyItem>().having(
          (item) => item.text,
          'text',
          "If you don't show up for your booking, it is treated like a cancellation less than 2 hours before, so there is no refund.",
        ),
        isA<LegalPolicyItem>().having(
          (item) => item.text,
          'text',
          'For boarding and sitting, the time is counted from your check-in time. Collecting your pet early does not give a partial refund.',
        ),
      ]),
    );

    expect(_policyText(LegalPoliciesCatalog.refundPolicy), const [
      'Your refund is calculated on the amount you actually paid, based on the cancellation timing.',
      'If the provider cancels a paid booking, you get 100% of what you paid back, automatically.',
      'Refunds go back to the account you paid from, within 5 to 7 working days.',
      'If something went wrong with your service, you can raise an issue in the app within 24 hours of the service ending. We review every case before any money is released.',
    ]);
    expect(_policyText(LegalPoliciesCatalog.termsAndConditions), const [
      'Booking works in three steps. You send a request. The provider has 60 minutes to accept, counted within their working hours. You then have 60 minutes to pay. Your booking is confirmed only after payment.',
      'A service starts only when the provider enters your OTP.',
      "Bookings can't be rescheduled. To change a time, cancel and book again.",
      'Providers on Pettxo are independent. Pettxo verifies them, but they run their own services.',
      'Using Pettxo means you agree to give accurate details, communicate respectfully, and use the platform lawfully. Pettxo will notify you before important policy changes take effect.',
    ]);
    expect(_policyText(LegalPoliciesCatalog.privacyPolicy), const [
      'Pettxo collects account, pet, booking, and device information to run the platform.',
      'Your name and phone number are shared with a provider only after your booking is paid and confirmed.',
      'Booking activity, such as response and cancellation history, is used for safety checks and to rank providers in search.',
      'Your data is stored on servers in India. You can update your details in app settings or contact hello@pettxo.com.',
    ]);
    expect(_policyText(LegalPoliciesCatalog.providerPolicy), const [
      'Providers are verified manually using a government ID and bank details before they can list.',
      'You have 60 minutes within your working hours to accept or decline a request. Declining is never penalised.',
      'Ignoring requests or cancelling paid bookings leads to temporary pauses. If you cancel a paid booking, the pet parent gets 100% back and you earn nothing for it.',
      'Payment for a service is released 24 hours after it ends, if no issue has been raised. If a pet parent cancels close to the service time, you get the provider share set out in the Cancellation Policy.',
    ]);
  });

  testWidgets('cancellation timing brackets render as nested policy details', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LegalPolicyDetailScreen(
          document: LegalPoliciesCatalog.cancellationPolicy,
        ),
      ),
    );

    expect(find.text('Cancellation Policy'), findsNWidgets(2));
    expect(
      find.text(
        'After payment, your refund depends on how much time is left before the service starts:',
      ),
      findsOneWidget,
    );
    expect(find.text('More than 24 hours before: 95% back'), findsOneWidget);
    expect(find.text('12 to 24 hours before: 75% back'), findsOneWidget);
    expect(find.text('6 to 12 hours before: 50% back'), findsOneWidget);
    expect(find.text('2 to 6 hours before: 25% back'), findsOneWidget);
    expect(find.text('Less than 2 hours before: no refund'), findsOneWidget);
    expect(find.text('Read full policy on website'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

List<String> _policyText(LegalPolicyDocument document) =>
    document.items.map((item) => item.text).toList(growable: false);
