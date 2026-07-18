class AuthActionException implements Exception {
  final String code;
  final String message;

  const AuthActionException({required this.code, required this.message});

  @override
  String toString() => message;
}
