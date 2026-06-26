import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        forceResendingToken: forceResendingToken,
        verificationCompleted: (credential) async {
          await verificationCompleted(credential);
        },
        verificationFailed: (e) async {
          await verificationFailed(_mapFirebaseError(e));
        },
        codeSent: (verificationId, resendToken) async {
          await codeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (verificationId) async {
          if (codeAutoRetrievalTimeout != null) {
            await codeAutoRetrievalTimeout(verificationId);
          }
        },
      );
    } on FirebaseAuthException catch (e) {
      await verificationFailed(_mapFirebaseError(e));
    } catch (_) {
      await verificationFailed("Unable to verify phone number right now.");
    }
  }

  Future<UserCredential> signInWithPhoneCredential({
    required String verificationId,
    required String smsCode,
  }) {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _auth.signInWithCredential(credential);
  }

  Future<UserCredential> signInWithCredential(PhoneAuthCredential credential) {
    return _auth.signInWithCredential(credential);
  }

  Future<void> logout() async {
    try {
      await PushNotificationService.instance
          .unregisterCurrentDeviceTokenForLogout();
    } catch (_) {
      // Token cleanup should not block sign-out.
    }
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
        return "Too many attempts. Try again later.";
      case 'invalid-verification-code':
        return "The OTP you entered is invalid.";
      case 'session-expired':
        return "This OTP has expired. Please request a new one.";
      case 'invalid-phone-number':
        return "Enter a valid phone number.";
      default:
        return "Authentication error. Please try again.";
    }
  }
}
