class Validators {

  static String? validateEmail(String email) {

    if (email.isEmpty) {
      return "Email cannot be empty";
    }

    final emailRegex =
        RegExp(r'^[\w\.-]+@([\w-]+\.)+[\w-]{2,4}$');

    if (!emailRegex.hasMatch(email)) {
      return "Invalid email format";
    }

    return null;
  }

  static String? validatePassword(String password) {

    if (password.isEmpty) {
      return "Password cannot be empty";
    }

    if (password.length < 6) {
      return "Password must be at least 6 characters";
    }

    if (password.contains(" ")) {
      return "Password cannot contain spaces";
    }

    return null;
  }
}