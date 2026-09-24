import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/widgets/app_buttons.dart';
import 'package:pettexo/features/profile/domain/models/profile_service_listing.dart';
import 'package:pettexo/features/profile/presentation/screens/service_detail_screen.dart';

ProfileServiceListing _service({
  String city = 'Pune',
  String state = 'Maharashtra',
}) {
  return ProfileServiceListing(
    id: 'service-1',
    ownerUserId: 'provider-1',
    ownerName: 'Nagpur Provider',
    title: 'Dog Walking',
    serviceType: 'Walking',
    description: 'Safe walks',
    rate: '₹500/session',
    location: 'Private exact address or stale owner location: Nagpur',
    serviceCity: city,
    serviceState: state,
    availability: 'Monday',
    duration: '60 minutes',
    petSize: 'Dog',
    rating: 'No reviews yet',
    distance: '',
    distanceKm: 12.5,
    latitude: 18.52,
    longitude: 73.86,
    imageUrl: '',
  );
}

Future<void> _pumpLocationSections(
  WidgetTester tester,
  ProfileServiceListing service,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              ServiceDetailAboutLocation(service: service),
              ServiceDetailLocationCard(service: service),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'about and bottom location use the same public service city and state',
    (tester) async {
      await _pumpLocationSections(tester, _service());

      expect(find.text('Pune, Maharashtra'), findsNWidgets(2));
      expect(find.textContaining('Nagpur'), findsNothing);
      expect(find.textContaining('Private exact address'), findsNothing);
      expect(find.text('LOCATION'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);

      final mapsButton = tester.widget<SecondaryButton>(
        find.widgetWithText(SecondaryButton, 'Open in Google Maps'),
      );
      expect(mapsButton.onPressed, isNotNull);
    },
  );

  testWidgets('missing public location never displays owner location', (
    tester,
  ) async {
    await _pumpLocationSections(tester, _service(city: 'Pune', state: ''));

    expect(find.text('Location unavailable'), findsNWidgets(2));
    expect(find.textContaining('Nagpur'), findsNothing);
    expect(find.textContaining('Private exact address'), findsNothing);
  });
}
