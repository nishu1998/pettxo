import 'package:flutter/material.dart';

class AppColors {
  static const Color primary = Color(0xFFF75927);
  static const Color secondary = Color(0xFFFF8A50);
  static const Color background = Color(0xFFFCF8F5);
  static const Color card = Colors.white;
  static const Color textDark = Color(0xFF1C1C1C);
  static const Color textGrey = Color(0xFF6B7280);
  static const Color gradientEnd = Color(0xFFFF8A50);
  static const Color gradientSoft = Color(0xFFFFB38D);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [primary, gradientEnd],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient brandGradientDiagonal = LinearGradient(
    colors: [primary, gradientEnd, gradientSoft],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
