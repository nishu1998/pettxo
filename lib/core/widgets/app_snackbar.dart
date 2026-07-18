import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

enum AppSnackbarTone { success, error, warning, info }

class AppSnackbar {
  static OverlayEntry? _currentEntry;
  static _TopGlassSnackbar? _currentSnackbar;
  static String? _lastMessage;
  static DateTime? _lastShownAt;

  static void success(
    BuildContext context, {
    required String message,
    String? title,
    Duration? duration,
  }) => showSuccess(context, message, title: title, duration: duration);

  static void error(
    BuildContext context, {
    required String message,
    String? title,
    Duration? duration,
  }) => showError(context, message, title: title, duration: duration);

  static void warning(
    BuildContext context, {
    required String message,
    String? title,
    Duration? duration,
  }) => showWarning(context, message, title: title, duration: duration);

  static void info(
    BuildContext context, {
    required String message,
    String? title,
    Duration? duration,
  }) => showInfo(context, message, title: title, duration: duration);

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
      duration: duration ?? const Duration(seconds: 5),
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

  static void dismissCurrent() {
    _currentSnackbar?.dismiss(immediate: true);
    _removeCurrentEntry();
  }

  static void _show(
    BuildContext context, {
    required String message,
    required AppSnackbarTone tone,
    String? title,
    Duration? duration,
  }) {
    if (!context.mounted) return;

    final trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) return;

    final now = DateTime.now();
    if (_lastMessage == trimmedMessage &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < const Duration(milliseconds: 1200)) {
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _lastMessage = trimmedMessage;
    _lastShownAt = now;

    _currentSnackbar?.dismiss(immediate: true);
    _removeCurrentEntry();

    late final OverlayEntry entry;
    final snackbar = _TopGlassSnackbar(
      message: trimmedMessage,
      title: title?.trim().isEmpty ?? true ? null : title!.trim(),
      tone: tone,
      duration: duration ?? const Duration(seconds: 3),
      onDismissed: () {
        if (identical(_currentEntry, entry)) {
          _removeCurrentEntry();
        }
      },
    );

    entry = OverlayEntry(
      builder: (context) => _TopGlassSnackbarHost(snackbar: snackbar),
    );

    _currentEntry = entry;
    _currentSnackbar = snackbar;
    overlay.insert(entry);
  }

  static void _removeCurrentEntry() {
    _currentEntry?.remove();
    _currentEntry = null;
    _currentSnackbar = null;
  }
}

class _TopGlassSnackbarHost extends StatefulWidget {
  const _TopGlassSnackbarHost({required this.snackbar});

  final _TopGlassSnackbar snackbar;

  @override
  State<_TopGlassSnackbarHost> createState() => _TopGlassSnackbarHostState();
}

class _TopGlassSnackbarHostState extends State<_TopGlassSnackbarHost>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _hideTimer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.snackbar.bindDismiss(_dismiss);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _controller.forward();
    _hideTimer = Timer(widget.snackbar.duration, _dismiss);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _dismiss(immediate: true);
    }
  }

  Future<void> _dismiss({bool immediate = false}) async {
    if (_dismissed) return;
    _dismissed = true;
    _hideTimer?.cancel();

    if (!immediate && mounted) {
      await _controller.reverse();
    }

    widget.snackbar.onDismissed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: _TopGlassSnackbarCard(
                      snackbar: widget.snackbar,
                      onClose: () => _dismiss(immediate: false),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopGlassSnackbar {
  _TopGlassSnackbar({
    required this.message,
    required this.title,
    required this.tone,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final String? title;
  final AppSnackbarTone tone;
  final Duration duration;
  final VoidCallback onDismissed;

  Future<void> Function({bool immediate})? _dismiss;

  void bindDismiss(Future<void> Function({bool immediate}) dismiss) {
    _dismiss = dismiss;
  }

  void dismiss({bool immediate = false}) {
    _dismiss?.call(immediate: immediate);
  }
}

class _TopGlassSnackbarCard extends StatelessWidget {
  const _TopGlassSnackbarCard({required this.snackbar, required this.onClose});

  final _TopGlassSnackbar snackbar;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final style = _SnackStyle.forTone(snackbar.tone);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xCC1A1A1D) : const Color(0xCCFFFFFF);
    final textColor = isDark ? Colors.white : AppColors.textDark;
    final subTextColor = isDark
        ? Colors.white.withValues(alpha: 0.8)
        : AppColors.textGrey.withValues(alpha: 0.92);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: style.color.withValues(alpha: isDark ? 0.28 : 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.10),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: style.color.withValues(alpha: isDark ? 0.16 : 0.09),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: isDark ? 0.18 : 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: style.color.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Icon(style.icon, color: style.color, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (snackbar.title != null) ...[
                          Text(
                            snackbar.title!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: textColor,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                        Text(
                          snackbar.message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: snackbar.title != null
                                ? subTextColor
                                : textColor,
                            fontWeight: snackbar.title != null
                                ? FontWeight.w500
                                : FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  visualDensity: VisualDensity.compact,
                  splashRadius: 18,
                  tooltip: 'Dismiss',
                  icon: Icon(
                    Icons.close_rounded,
                    color: subTextColor,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SnackStyle {
  const _SnackStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  static _SnackStyle forTone(AppSnackbarTone tone) {
    return switch (tone) {
      AppSnackbarTone.success => const _SnackStyle(
        icon: Icons.check_circle_rounded,
        color: Color(0xFF26B36E),
      ),
      AppSnackbarTone.error => const _SnackStyle(
        icon: Icons.error_rounded,
        color: Color(0xFFE06464),
      ),
      AppSnackbarTone.warning => const _SnackStyle(
        icon: Icons.warning_rounded,
        color: Color(0xFFE1A320),
      ),
      AppSnackbarTone.info => const _SnackStyle(
        icon: Icons.info_rounded,
        color: AppColors.primary,
      ),
    };
  }
}
