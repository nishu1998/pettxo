import 'package:flutter/material.dart';
import '../core/widgets/app_buttons.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;

  const CustomButton({super.key, required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GradientButton(label: text, onPressed: onPressed);
  }
}
