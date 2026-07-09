import 'package:firebase_auth/firebase_auth.dart';

class AuthResult {
  final User? user;
  final String? error;
  final String? errorCode;

  AuthResult({this.user, this.error, this.errorCode});

  bool get isSuccess => user != null;
}
