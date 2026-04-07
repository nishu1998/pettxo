import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

enum AppFeedbackTone { success, error, info }

class AppFeedback {
  static void show(
    BuildContext context, {
    required String message,
    AppFeedbackTone tone = AppFeedbackTone.info,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        content: _FeedbackCard(message: message, tone: tone),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final String message;
  final AppFeedbackTone tone;

  const _FeedbackCard({required this.message, required this.tone});

  @override
  Widget build(BuildContext context) {
    final (icon, gradient) = switch (tone) {
      AppFeedbackTone.success => (
        Icons.check_rounded,
        const LinearGradient(colors: [Color(0xFF23B26D), Color(0xFF4BD38B)]),
      ),
      AppFeedbackTone.error => (
        Icons.close_rounded,
        const LinearGradient(colors: [Color(0xFFE15656), Color(0xFFFF8A80)]),
      ),
      AppFeedbackTone.info => (
        Icons.info_outline_rounded,
        AppColors.brandGradient,
      ),
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
