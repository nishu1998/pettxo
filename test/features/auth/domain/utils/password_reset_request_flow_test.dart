import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/auth/domain/models/password_reset_request_result.dart';
import 'package:pettexo/features/auth/domain/utils/password_reset_request_flow.dart';

void main() {
  test('request flow rejects invalid email before backend call', () async {
    var approveCalled = false;
    var sendCalled = false;

    final result = await runPasswordResetRequestFlow(
      email: 'bad-email',
      approveRequest: (_) async {
        approveCalled = true;
      },
      sendResetEmail: (_) async {
        sendCalled = true;
      },
      mapError: (_, stackTrace, normalizedEmail) => PasswordResetRequestResult(
        status: PasswordResetRequestStatus.unknownError,
        normalizedEmail: normalizedEmail,
        message: 'unexpected',
      ),
    );

    expect(result.status, PasswordResetRequestStatus.invalidEmail);
    expect(approveCalled, isFalse);
    expect(sendCalled, isFalse);
  });

  test('request flow sends reset email exactly once after approval', () async {
    var approveCalls = 0;
    var sendCalls = 0;

    final result = await runPasswordResetRequestFlow(
      email: '  Person@Example.com ',
      approveRequest: (_) async {
        approveCalls += 1;
      },
      sendResetEmail: (_) async {
        sendCalls += 1;
      },
      mapError: (_, stackTrace, normalizedEmail) => PasswordResetRequestResult(
        status: PasswordResetRequestStatus.unknownError,
        normalizedEmail: normalizedEmail,
        message: 'unexpected',
      ),
    );

    expect(result.status, PasswordResetRequestStatus.sent);
    expect(result.normalizedEmail, 'person@example.com');
    expect(approveCalls, 1);
    expect(sendCalls, 1);
  });

  test('request flow does not send reset email when backend rejects', () async {
    var sendCalls = 0;

    final result = await runPasswordResetRequestFlow(
      email: 'person@example.com',
      approveRequest: (_) async {
        throw StateError('phone-only');
      },
      sendResetEmail: (_) async {
        sendCalls += 1;
      },
      mapError: (error, _, normalizedEmail) => PasswordResetRequestResult(
        status: PasswordResetRequestStatus.phoneOnlyAccount,
        normalizedEmail: normalizedEmail,
        message:
            'This account does not have a password. Sign in using your phone number.',
      ),
    );

    expect(result.status, PasswordResetRequestStatus.phoneOnlyAccount);
    expect(sendCalls, 0);
  });
}
