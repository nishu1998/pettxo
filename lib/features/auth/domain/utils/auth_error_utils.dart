import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/auth_action_exception.dart';

String mapFirebaseAuthErrorCode(String code) {
  switch (code) {
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
    case 'credential-already-in-use':
      return "This phone number is already linked to another Pettxo account.";
    case 'account-exists-with-different-credential':
      return "An account already exists with different sign-in credentials.";
    case 'provider-already-linked':
      return "This sign-in method is already linked to your account.";
    case 'invalid-credential':
      return "This sign-in credential is invalid or has expired. Please try again.";
    case 'requires-recent-login':
      return "Please sign in again before retrying this security-sensitive action.";
    case 'user-disabled':
      return "This account has been disabled. Please contact Pettxo support.";
    case 'username-taken':
      return "That username is already taken.";
    case 'invalid-username':
      return "Choose a valid username using 3-20 lowercase letters, numbers, dots, or underscores.";
    case 'invalid-display-name':
      return "Enter your name to continue.";
    case 'invalid-profile-role':
      return "Choose your Pettxo profile type and try again.";
    case 'invalid-state':
      return "Select your state to continue.";
    case 'invalid-city':
      return "Select your city to continue.";
    case 'legal-acceptance-required':
      return "Please accept the required Pettxo terms to continue.";
    case 'provider-agreement-required':
      return "Please accept the Service Provider Agreement to continue.";
    case 'phone-verification-required':
      return "Verify your phone number before completing your Pettxo profile.";
    case 'username-reservation-mismatch':
      return "Pettxo could not verify your current username ownership. Please refresh and try again.";
    default:
      return "Authentication error. Please try again.";
  }
}

AuthActionException mapFirebaseAuthException(FirebaseAuthException exception) {
  return AuthActionException(
    code: exception.code,
    message: mapFirebaseAuthErrorCode(exception.code),
  );
}

AuthActionException mapFunctionsActionException(
  FirebaseFunctionsException error,
) {
  final details = error.details;
  String? appCode;
  if (details is Map) {
    final rawCode = details['appCode'];
    if (rawCode is String && rawCode.trim().isNotEmpty) {
      appCode = rawCode.trim();
    }
  }
  final code = appCode ?? error.code;
  return AuthActionException(
    code: code,
    message: mapFirebaseAuthErrorCode(code),
  );
}
