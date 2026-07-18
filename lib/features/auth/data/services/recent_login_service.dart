import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/auth_action_exception.dart';
import 'auth_service.dart';

class RecentLoginService {
  final AuthService _authService;

  RecentLoginService({AuthService? authService})
    : _authService = authService ?? AuthService();

  Future<void> reauthenticateWithPassword({
    required String currentPassword,
  }) async {
    await _authService.reauthenticateCurrentUserWithPassword(
      currentPassword: currentPassword,
    );
  }

  Future<void> sendPhoneReauthenticationCode({
    required String phoneNumber,
    required Future<void> Function(String verificationId, int? resendToken)
    codeSent,
    required Future<void> Function(String message) verificationFailed,
    required Future<void> Function(PhoneAuthCredential credential)
    verificationCompleted,
    Future<void> Function(String verificationId)? codeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) async {
    await _authService.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      codeSent: codeSent,
      verificationFailed: verificationFailed,
      verificationCompleted: verificationCompleted,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      forceResendingToken: forceResendingToken,
    );
  }

  Future<void> reauthenticateWithPhoneOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    await _authService.reauthenticateCurrentUserWithPhoneCredential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
  }

  String requireCurrentUserPhoneNumber() {
    final phoneNumber = _authService.currentUser?.phoneNumber?.trim() ?? '';
    if (phoneNumber.isEmpty) {
      throw const AuthActionException(
        code: 'missing-phone',
        message: 'No verified phone number is linked to this account.',
      );
    }
    return phoneNumber;
  }
}
