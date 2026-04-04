import 'package:flutter/material.dart';

class OnboardingButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const OnboardingButton({
    super.key,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 55,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color(0xFFF75927),
              Color(0xFFFF8A50),
            ],
          ),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF75927).withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}