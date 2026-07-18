import 'package:flutter/material.dart';
import '../core/widgets/app_buttons.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final AppButtonSize size;
  final double? labelFontSize;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.size = AppButtonSize.regular,
    this.labelFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return GradientButton(
      label: text,
      onPressed: onPressed,
      size: size,
      labelFontSize: labelFontSize,
    );
  }
}
