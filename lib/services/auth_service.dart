import 'package:firebase_auth/firebase_auth.dart';
import '../models/auth_result.dart';

class AuthService {

  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// SIGN UP USER
  Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {

    try {

      UserCredential credential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      return AuthResult(user: credential.user);

    }

    on FirebaseAuthException catch (e) {
      return AuthResult(error: _mapFirebaseError(e));
    }

    catch (e) {
      return AuthResult(error: "Unexpected error occurred.");
    }

  }

  /// LOGIN USER
  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {

    try {

      UserCredential credential =
          await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      return AuthResult(user: credential.user);

    }

    on FirebaseAuthException catch (e) {
      return AuthResult(error: _mapFirebaseError(e));
    }

    catch (e) {
      return AuthResult(error: "Unexpected login error.");
    }

  }

  /// LOGOUT
  Future<void> logout() async {
    await _auth.signOut();
  }

  /// CURRENT USER
  User? get currentUser => _auth.currentUser;

  /// AUTH STATE STREAM (very important later)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// MAP FIREBASE ERRORS
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

      default:
        return "Authentication error. Please try again.";
    }

  }

}