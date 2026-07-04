import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/services/legal_acceptance_session_service.dart';
import '../../../../core/services/push_notification_service.dart';
import '../../domain/models/auth_result.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-south1',
  );

  Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      return AuthResult(user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(error: _mapFirebaseError(e));
    } catch (_) {
      return AuthResult(error: "Unexpected error occurred.");
    }
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return AuthResult(user: credential.user);
    } on FirebaseAuthException catch (e) {
      return AuthResult(error: _mapFirebaseError(e));
    } catch (_) {
      return AuthResult(error: "Unexpected login error.");
    }
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Future<void> Function(PhoneAuthCredential credential)
    verificationCompleted,
    required Future<void> Function(String verificationId, int? resendToken)
    codeSent,
    required Future<void> Function(String message) verificationFailed,
    Future<void> Function(String verificationId)? codeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) async {
    try {
      _debugLog(
        'verifyPhoneNumber:start phone=${_redactPhoneNumber(phoneNumber)} '
        'forceResendingTokenPresent=${forceResendingToken != null}',
      );
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (credential) async {
          _debugLog(
            'verifyPhoneNumber:verificationCompleted '
            'phone=${_redactPhoneNumber(phoneNumber)}',
          );
          await verificationCompleted(credential);
        },
        verificationFailed: (e) async {
          _logFirebaseAuthException('verifyPhoneNumber:verificationFailed', e);
          final message = _mapFirebaseError(e);
          await verificationFailed(message);
        },
        codeSent: (verificationId, resendToken) async {
          _debugLog(
            'verifyPhoneNumber:codeSent '
            'phone=${_redactPhoneNumber(phoneNumber)} '
            'verificationIdLength=${verificationId.length} '
            'resendTokenPresent=${resendToken != null}',
          );
          await codeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (verificationId) async {
          _debugLog(
            'verifyPhoneNumber:codeAutoRetrievalTimeout '
            'phone=${_redactPhoneNumber(phoneNumber)} '
            'verificationIdLength=${verificationId.length}',
          );
          if (codeAutoRetrievalTimeout != null) {
            await codeAutoRetrievalTimeout(verificationId);
          }
        },
      );
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('verifyPhoneNumber:threw', e);
      final message = _mapFirebaseError(e);
      await verificationFailed(message);
    } catch (error, stackTrace) {
      _logUnexpectedError('verifyPhoneNumber:unexpected', error, stackTrace);
      await verificationFailed("Unable to verify phone number right now.");
    }
  }

  Future<UserCredential> signInWithPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      _debugLog(
        'signInWithPhoneCredential:start '
        'verificationIdLength=${verificationId.length} '
        'smsCodeLength=${smsCode.length}',
      );
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('signInWithPhoneCredential:failed', e);
      throw Exception(_mapFirebaseError(e));
    } catch (error, stackTrace) {
      _logUnexpectedError(
        'signInWithPhoneCredential:unexpected',
        error,
        stackTrace,
      );
      throw Exception('Unable to verify the OTP right now.');
    }
  }

  Future<UserCredential> signInWithCredential(
    PhoneAuthCredential credential,
  ) async {
    try {
      _debugLog('signInWithCredential:start provider=phone');
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      _logFirebaseAuthException('signInWithCredential:failed', e);
      throw Exception(_mapFirebaseError(e));
    } catch (error, stackTrace) {
      _logUnexpectedError('signInWithCredential:unexpected', error, stackTrace);
      throw Exception('Unable to complete phone sign-in right now.');
    }
  }

  Future<void> logout() async {
    try {
      await PushNotificationService.instance
          .unregisterCurrentDeviceTokenForLogout();
    } catch (_) {
      // Token cleanup should not block sign-out.
    }
    LegalAcceptanceSessionService.instance.clearSignupConsent();
    await _auth.signOut();
  }

  Future<String> requestAccountDeletion() async {
    final callable = _functions.httpsCallable('requestAccountDeletion');
    final result = await callable.call<Map<String, dynamic>>();
    final data = Map<String, dynamic>.from(result.data);
    return (data['message'] as String? ?? 'Account deletion requested.').trim();
  }

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  String _mapFirebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return "Password must be at least 6 characters.";
      case 'email-already-in-use':
        return "An account already exists with this email.";
      case 'invalid-email':
        return "Invalid email format.";
      case 'user-not-found':
        return "No user found with this email.";
      case 'wrong-password':
        return "Incorrect password.";
      case 'network-request-failed':
        return "Network error. Check your internet connection.";
      case 'too-many-requests':
        return "Too many verification attempts for this phone number. Please wait 30 minutes before trying again or request a new OTP later.";
      case 'invalid-verification-code':
        return "The OTP you entered is invalid.";
      case 'session-expired':
        return "This OTP has expired. Please request a new one.";
      case 'invalid-phone-number':
        return "Enter a valid phone number.";
      case 'operation-not-allowed':
        return "Phone sign-in is not enabled for this Firebase project.";
      case 'app-not-authorized':
        return "This app build is not authorized for Firebase Phone Authentication. Check the Firebase app fingerprints and phone auth setup.";
      case 'invalid-app-credential':
        return "Firebase could not verify this app build. Check Play Integrity, SHA fingerprints, and Firebase app verification settings.";
      case 'missing-client-identifier':
        return "This app is missing the Firebase client configuration required for phone sign-in.";
      case 'captcha-check-failed':
        return "The app verification check failed. Please try again.";
      case 'quota-exceeded':
        return "SMS verification is temporarily unavailable due to too many attempts. Please wait 30 minutes before trying again.";
      case 'invalid-verification-id':
        return "This verification session is invalid. Please request a new OTP.";
      default:
        return "Authentication error. Please try again.";
    }
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('AuthService $message');
    }
  }

  void _logFirebaseAuthException(String context, FirebaseAuthException error) {
    if (!kDebugMode) return;
    debugPrint(
      'AuthService $context code=${error.code} '
      'message=${error.message ?? error.toString()}',
    );
    if (error.stackTrace != null) {
      debugPrintStack(stackTrace: error.stackTrace);
    }
  }

  void _logUnexpectedError(
    String context,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;
    debugPrint('AuthService $context error=$error');
    debugPrintStack(stackTrace: stackTrace);
  }

  String _redactPhoneNumber(String phoneNumber) {
    final trimmed = phoneNumber.trim();
    if (trimmed.length <= 4) return trimmed;
    final suffix = trimmed.substring(trimmed.length - 4);
    return '***$suffix';
  }
}
