import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/auth/domain/models/email_verification_mode.dart';
import 'package:pettexo/features/auth/domain/utils/email_verification_controller.dart';
import 'package:pettexo/features/auth/presentation/screens/email_verification_screen.dart';

void main() {
  testWidgets(
    'verified change returns to a complete authenticated destination',
    (tester) async {
      await tester.pumpWidget(_TestApp(controller: _controller()));
      await _openVerification(tester);

      await tester.tap(find.text('I have verified'));
      await tester.pumpAndSettle();

      expect(find.text('Account & Security'), findsOneWidget);
      expect(find.text('Authenticated body'), findsOneWidget);
      expect(
        find.byKey(const Key('authenticated-bottom-navigation')),
        findsOneWidget,
      );
      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(find.text('Home selected'), findsOneWidget);
    },
  );

  testWidgets('pending verification stays usable and does not navigate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(controller: _controller(EmailVerificationRefreshResult.pending)),
    );
    await _openVerification(tester);

    await tester.tap(find.text('I have verified'));
    await tester.pump();

    expect(find.text('Verify Linked Email'), findsOneWidget);
    expect(find.text('I have verified'), findsOneWidget);
    expect(find.textContaining('still unverified'), findsOneWidget);
  });

  testWidgets('double tap runs one completion and navigation', (tester) async {
    final completer = Completer<EmailVerificationRefreshResult>();
    var checks = 0;
    await tester.pumpWidget(
      _TestApp(
        controller: _DelegatingController(() {
          checks += 1;
          return completer.future;
        }),
      ),
    );
    await _openVerification(tester);

    await tester.tap(find.text('I have verified'));
    await tester.pump();
    await tester.tap(find.text('Checking...'));
    expect(checks, 1);

    completer.complete(EmailVerificationRefreshResult.verified);
    await tester.pumpAndSettle();
    expect(find.text('Account & Security'), findsOneWidget);
  });

  testWidgets('check failure leaves verification screen usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        controller: _DelegatingController(
          () async => throw StateError('network unavailable'),
        ),
      ),
    );
    await _openVerification(tester);

    await tester.tap(find.text('I have verified'));
    await tester.pump();

    expect(find.text('Verify Linked Email'), findsOneWidget);
    expect(find.text('I have verified'), findsOneWidget);
    expect(find.textContaining('network unavailable'), findsOneWidget);
  });

  testWidgets('invalidated auth session replaces the full route stack', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        controller: _controller(
          EmailVerificationRefreshResult.reauthenticationRequired,
        ),
      ),
    );
    await _openVerification(tester);

    await tester.tap(find.text('I have verified'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in required'), findsOneWidget);
    expect(find.text('Account & Security'), findsNothing);
    expect(
      find.byKey(const Key('authenticated-bottom-navigation')),
      findsNothing,
    );
  });

  testWidgets('background and resume preserve verification state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(controller: _controller(EmailVerificationRefreshResult.pending)),
    );
    await _openVerification(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.text('Verify Linked Email'), findsOneWidget);
    expect(find.text('I have verified'), findsOneWidget);
  });
}

EmailVerificationController _controller([
  EmailVerificationRefreshResult result =
      EmailVerificationRefreshResult.verified,
]) => _DelegatingController(() async => result);

class _DelegatingController extends EmailVerificationController {
  _DelegatingController(this.onCheck)
    : super(
        reloadCurrentUser: _noop,
        refreshIdToken: _noop,
        currentUid: _uid,
        isEmailVerified: _verified,
        syncTrustedAuthIdentity: _noop,
        isSessionInvalidError: _notInvalid,
        expectedUid: 'stable-uid',
      );

  final Future<EmailVerificationRefreshResult> Function() onCheck;

  static Future<void> _noop() async {}
  static String _uid() => 'stable-uid';
  static bool _verified() => true;
  static bool _notInvalid(Object _) => false;

  @override
  Future<EmailVerificationRefreshResult> refreshVerificationStatus() =>
      onCheck();
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.controller});

  final EmailVerificationController controller;

  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: _AuthenticatedDestination(controller: controller));
}

class _AuthenticatedDestination extends StatefulWidget {
  const _AuthenticatedDestination({required this.controller});

  final EmailVerificationController controller;

  @override
  State<_AuthenticatedDestination> createState() =>
      _AuthenticatedDestinationState();
}

class _AuthenticatedDestinationState extends State<_AuthenticatedDestination> {
  var _homeSelected = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account & Security')),
    body: Center(
      child: Text(_homeSelected ? 'Home selected' : 'Authenticated body'),
    ),
    bottomNavigationBar: BottomNavigationBar(
      key: const Key('authenticated-bottom-navigation'),
      currentIndex: _homeSelected ? 1 : 0,
      onTap: (index) => setState(() => _homeSelected = index == 1),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () async {
        final didVerify = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => EmailVerificationScreen(
              mode: EmailVerificationMode.nonBlockingLinkedEmail,
              displayEmailOverride: 'new@example.com',
              expectedVerifiedEmail: 'new@example.com',
              expectedUid: 'stable-uid',
              verificationController: widget.controller,
              reauthenticationDestinationBuilder: (_) =>
                  const Scaffold(body: Center(child: Text('Sign in required'))),
            ),
          ),
        );
        if (!mounted || didVerify != true) return;
        setState(() {});
      },
      child: const Icon(Icons.email),
    ),
  );
}

Future<void> _openVerification(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.email));
  await tester.pumpAndSettle();
  expect(find.text('Verify Linked Email'), findsOneWidget);
}
