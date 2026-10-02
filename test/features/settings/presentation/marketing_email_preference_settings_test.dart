import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/profile/domain/models/user_profile.dart';
import 'package:pettexo/features/settings/domain/models/app_settings.dart';
import 'package:pettexo/features/settings/presentation/screens/settings_screen.dart';

void main() {
  testWidgets('Settings exposes an independent optional marketing email toggle', (
    tester,
  ) async {
    var updateCount = 0;
    bool? savedValue;
    final profile = UserProfile.fromMap({
      'uid': 'user-1',
      'displayName': 'Pet Parent',
      'username': 'petparent',
      'role': 'petParent',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          loadSettingsOverride: () async => const AppSettings.defaults(),
          loadProfileOverride: () async => profile,
          loadProviderOnboardingOverride: () async => throw Exception('none'),
          loadMarketingEmailPreferenceOverride: () async => false,
          updateMarketingEmailPreferenceOverride: (enabled) async {
            updateCount++;
            savedValue = enabled;
            return enabled;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('EMAIL PREFERENCES'), findsOneWidget);
    expect(find.text('Offers & Pettxo updates'), findsOneWidget);
    expect(
      find.text(
        'Optional offers and news. Essential account and service emails are unaffected.',
      ),
      findsOneWidget,
    );

    final switchFinder = find.byType(Switch).last;
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(updateCount, 1);
    expect(savedValue, isTrue);
  });
}
