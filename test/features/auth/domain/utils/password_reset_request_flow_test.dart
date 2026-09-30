import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/auth/domain/models/password_reset_request_result.dart';
import 'package:pettexo/features/auth/domain/utils/password_reset_request_flow.dart';

void main() {
  test('request flow rejects invalid email before backend call', () async {
    var requestCalled = false;

    final result = await runPasswordResetRequestFlow(
      email: 'bad-email',
      requestReset: (_) async {
        requestCalled = true;
      },
      mapError: (_, stackTrace, normalizedEmail) => PasswordResetRequestResult(
        status: PasswordResetRequestStatus.unknownError,
        normalizedEmail: normalizedEmail,
        message: 'unexpected',
      ),
    );

    expect(result.status, PasswordResetRequestStatus.invalidEmail);
    expect(requestCalled, isFalse);
  });

  test('request flow calls the V2 backend exactly once', () async {
    var requestCalls = 0;

    final result = await runPasswordResetRequestFlow(
      email: '  Person@Example.com ',
      requestReset: (_) async {
        requestCalls += 1;
      },
      mapError: (_, stackTrace, normalizedEmail) => PasswordResetRequestResult(
        status: PasswordResetRequestStatus.unknownError,
        normalizedEmail: normalizedEmail,
        message: 'unexpected',
      ),
    );

    expect(result.status, PasswordResetRequestStatus.sent);
    expect(result.normalizedEmail, 'person@example.com');
    expect(requestCalls, 1);
    expect(
      result.message,
      "If an account exists for that email, we've sent password reset instructions.",
    );
  });

  test('request flow maps backend transport failures', () async {
    var requestCalls = 0;

    final result = await runPasswordResetRequestFlow(
      email: 'person@example.com',
      requestReset: (_) async {
        requestCalls += 1;
        throw StateError('backend unavailable');
      },
      mapError: (error, _, normalizedEmail) => PasswordResetRequestResult(
        status: PasswordResetRequestStatus.unknownError,
        normalizedEmail: normalizedEmail,
        message: 'Unable to request a password reset right now.',
      ),
    );

    expect(result.status, PasswordResetRequestStatus.unknownError);
    expect(requestCalls, 1);
  });
}
