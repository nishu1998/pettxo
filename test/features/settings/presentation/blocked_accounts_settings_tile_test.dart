import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/blocking/data/blocked_relationship_repository.dart';
import 'package:pettexo/features/blocking/presentation/screens/blocked_users_screen.dart';
import 'package:pettexo/features/profile/domain/models/user_profile.dart';
import 'package:pettexo/features/settings/domain/models/app_settings.dart';
import 'package:pettexo/features/settings/presentation/screens/settings_screen.dart';

void main() {
  Future<void> pumpSettings(
    WidgetTester tester,
    _EmptyBlockingRepository repository,
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
          blockedRelationshipRepository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-blocked-accounts')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Blocked accounts is listed in the ACCOUNT section', (
    tester,
  ) async {
    await pumpSettings(tester, _EmptyBlockingRepository());

    final tile = find.byKey(const ValueKey('settings-blocked-accounts'));
    expect(tile, findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.text('Blocked accounts')),
      findsOneWidget,
    );
    expect(find.text('See and unblock accounts you blocked'), findsOneWidget);
    expect(find.text('Blocked Users'), findsNothing);

    // The tile shares the ACCOUNT card with Account & Security and is not in
    // the MORE card.
    // The nearest Column that holds both the tile and Account & Security is
    // the ACCOUNT card; it must not reach into the MORE card.
    final columns = find.ancestor(of: tile, matching: find.byType(Column));
    Finder? accountCard;
    for (var i = 0; i < columns.evaluate().length; i++) {
      final candidate = columns.at(i);
      if (find
          .descendant(of: candidate, matching: find.text('Account & Security'))
          .evaluate()
          .isNotEmpty) {
        accountCard = candidate;
        break;
      }
    }
    expect(accountCard, isNotNull);
    expect(
      find.descendant(of: accountCard!, matching: find.text('My offers')),
      findsNothing,
    );
    expect(
      find.descendant(of: accountCard, matching: find.text('Sign out')),
      findsNothing,
    );
    final securityY = tester.getTopLeft(find.text('Account & Security')).dy;
    expect(securityY, lessThan(tester.getTopLeft(tile).dy));
    final accountLabel = find.text('ACCOUNT', skipOffstage: false);
    expect(accountLabel, findsOneWidget);
    expect(
      tester.getTopLeft(accountLabel).dy,
      lessThan(tester.getTopLeft(tile).dy),
    );
  });

  testWidgets('tapping Blocked accounts opens the blocked accounts screen', (
    tester,
  ) async {
    final repository = _EmptyBlockingRepository();
    await pumpSettings(tester, repository);

    await tester.tap(find.byKey(const ValueKey('settings-blocked-accounts')));
    await tester.pumpAndSettle();

    expect(find.byType(BlockedUsersScreen), findsOneWidget);
    expect(find.text('Blocked accounts'), findsOneWidget);
    expect(find.text("You haven't blocked anyone."), findsOneWidget);
    expect(repository.loadCalls, 1);
  });
}

class _EmptyBlockingRepository extends BlockedRelationshipRepository {
  _EmptyBlockingRepository()
    : super(functions: _NoopFunctions(), currentUidOverride: () => 'user-1');

  int loadCalls = 0;

  @override
  Future<OutgoingBlockedUsersPage> loadOutgoingBlockedUsers({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = 20,
  }) async {
    loadCalls += 1;
    return const OutgoingBlockedUsersPage(
      users: [],
      cursor: null,
      hasMore: false,
    );
  }
}

class _NoopFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
