import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/auth/domain/models/password_reset_request_result.dart';
import 'package:pettexo/features/auth/presentation/screens/signin_screen.dart';

void main() {
  testWidgets(
    'forgot password success state has no Done button and can go back to sign in',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (_) => ForgotPasswordDialog(
                          initialEmail: 'person@example.com',
                          requestPasswordResetOverride: (email) async {
                            return PasswordResetRequestResult(
                              status: PasswordResetRequestStatus.sent,
                              normalizedEmail: email.trim().toLowerCase(),
                              message:
                                  'Check your inbox and follow the link to create a new password.',
                            );
                          },
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'person@example.com');
      await tester.tap(find.text('Send Reset Link'));
      await tester.pumpAndSettle();

      expect(find.text('Password reset email sent'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      expect(find.text('Back to Sign In'), findsOneWidget);

      await tester.tap(find.text('Back to Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Reset Password'), findsNothing);
    },
  );
}
