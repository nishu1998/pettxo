import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

enum AppSnackbarTone { success, error, warning, info }

class AppSnackbar {
  static void showSuccess(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      title: title,
      tone: AppSnackbarTone.success,
      duration: duration,
    );
  }

  static void showError(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      title: title,
      tone: AppSnackbarTone.error,
      duration: duration,
    );
  }

  static void showWarning(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      title: title,
      tone: AppSnackbarTone.warning,
      duration: duration,
    );
  }

  static void showInfo(
    BuildContext context,
    String message, {
    String? title,
    Duration? duration,
  }) {
    _show(
      context,
      message: message,
      title: title,
      tone: AppSnackbarTone.info,
      duration: duration,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required AppSnackbarTone tone,
    String? title,
    Duration? duration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        padding: EdgeInsets.zero,
        duration: duration ?? const Duration(seconds: 3),
        content: _AppSnackbarCard(
          message: message,
          title: title,
          tone: tone,
          onClose: messenger.hideCurrentSnackBar,
        ),
      ),
    );
  }
}

class _AppSnackbarCard extends StatelessWidget {
  final String message;
  final String? title;
  final AppSnackbarTone tone;
  final VoidCallback onClose;

  const _AppSnackbarCard({
    required this.message,
    required this.title,
    required this.tone,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final style = _SnackStyle.forTone(tone);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: style.color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: style.color.withValues(alpha: 0.12),
            blurRadius: 26,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: style.gradient),
                child: const SizedBox(width: 5),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: style.gradient,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: style.color.withValues(alpha: 0.28),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Icon(style.icon, color: Colors.white, size: 21),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null && title!.trim().isNotEmpty) ...[
                          Text(
                            title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textDark,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                        Text(
                          message,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: onClose,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Dismiss',
                    icon: Icon(
                      Icons.close_rounded,
                      color: AppColors.textGrey.withValues(alpha: 0.72),
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SnackStyle {
  final IconData icon;
  final Color color;
  final LinearGradient gradient;

  const _SnackStyle({
    required this.icon,
    required this.color,
    required this.gradient,
  });

  static _SnackStyle forTone(AppSnackbarTone tone) {
    return switch (tone) {
      AppSnackbarTone.success => const _SnackStyle(
        icon: Icons.check_rounded,
        color: Color(0xFF23B26D),
        gradient: LinearGradient(
          colors: [Color(0xFF1EA965), Color(0xFF62D69A)],
        ),
      ),
      AppSnackbarTone.error => const _SnackStyle(
        icon: Icons.close_rounded,
        color: Color(0xFFE15656),
        gradient: LinearGradient(
          colors: [Color(0xFFE34D4D), Color(0xFFFF8A80)],
        ),
      ),
      AppSnackbarTone.warning => const _SnackStyle(
        icon: Icons.priority_high_rounded,
        color: Color(0xFFE6A21A),
        gradient: LinearGradient(
          colors: [Color(0xFFE6A21A), Color(0xFFFFC766)],
        ),
      ),
      AppSnackbarTone.info => const _SnackStyle(
        icon: Icons.info_outline_rounded,
        color: AppColors.primary,
        gradient: AppColors.brandGradient,
      ),
    };
  }
}
