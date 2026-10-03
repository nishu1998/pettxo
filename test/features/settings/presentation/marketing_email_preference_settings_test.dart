import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/profile/domain/models/user_profile.dart';
import 'package:pettexo/features/settings/domain/models/app_settings.dart';
import 'package:pettexo/features/settings/presentation/screens/email_preferences_screen.dart';
import 'package:pettexo/features/settings/presentation/screens/settings_screen.dart';

void main() {
  testWidgets('main Settings no longer renders marketing email controls', (
    tester,
  ) async {
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Account & Security'),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('EMAIL PREFERENCES'), findsNothing);
    expect(find.text('Offers & Pettxo updates'), findsNothing);
    expect(find.text('Account & Security'), findsOneWidget);
  });

  testWidgets('Email Preferences preserves and saves the existing preference', (
    tester,
  ) async {
    var updateCount = 0;
    bool? savedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: EmailPreferencesScreen(
          loadPreferenceOverride: () async => true,
          updatePreferenceOverride: (enabled) async {
            updateCount++;
            savedValue = enabled;
            return enabled;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Email Preferences'), findsOneWidget);
    expect(find.text('Offers & Pettxo updates'), findsOneWidget);
    expect(
      find.text(
        'Optional offers and news. Essential account and service emails are unaffected.',
      ),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(updateCount, 1);
    expect(savedValue, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });
}
