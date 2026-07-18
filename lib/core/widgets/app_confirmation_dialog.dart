import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'app_snackbar.dart';

class AppConfirmationDialog {
  AppConfirmationDialog._();

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String message,
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Confirm',
    bool isDestructive = false,
    Future<void> Function()? onConfirm,
    String? errorMessage,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.16),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        return _ConfirmationDialogRoute(
          parentContext: context,
          title: title,
          message: message,
          cancelLabel: cancelLabel,
          confirmLabel: confirmLabel,
          isDestructive: isDestructive,
          onConfirm: onConfirm,
          errorMessage: errorMessage,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static Future<bool?> showPhraseConfirmation({
    required BuildContext context,
    required String title,
    required String message,
    required String confirmationPhrase,
    String inputLabel = 'Type to confirm',
    String cancelLabel = 'Cancel',
    String confirmLabel = 'Confirm',
    bool isDestructive = true,
    Future<void> Function()? onConfirm,
    String? errorMessage,
    String? helperMessage,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.16),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        return _PhraseConfirmationDialogRoute(
          parentContext: context,
          title: title,
          message: message,
          confirmationPhrase: confirmationPhrase,
          inputLabel: inputLabel,
          cancelLabel: cancelLabel,
          confirmLabel: confirmLabel,
          isDestructive: isDestructive,
          onConfirm: onConfirm,
          errorMessage: errorMessage,
          helperMessage: helperMessage,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _ConfirmationDialogRoute extends StatefulWidget {
  const _ConfirmationDialogRoute({
    required this.parentContext,
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.isDestructive,
    required this.onConfirm,
    required this.errorMessage,
  });

  final BuildContext parentContext;
  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final bool isDestructive;
  final Future<void> Function()? onConfirm;
  final String? errorMessage;

  @override
  State<_ConfirmationDialogRoute> createState() =>
      _ConfirmationDialogRouteState();
}

class _ConfirmationDialogRouteState extends State<_ConfirmationDialogRoute> {
  bool _isProcessing = false;

  Future<void> _handleCancel() async {
    if (_isProcessing || !mounted) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _handleConfirm() async {
    if (_isProcessing) return;
    if (widget.onConfirm == null) {
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      await widget.onConfirm!.call();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      final messengerContext = widget.parentContext;
      if (!messengerContext.mounted) return;
      AppSnackbar.error(
        messengerContext,
        message:
            widget.errorMessage ?? 'Something went wrong. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final confirmColor = widget.isDestructive
        ? const Color(0xFFE06A6A)
        : AppColors.primary;
    final surface = isDark ? const Color(0xCC1D1B1A) : const Color(0xCCFFFFFF);
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final messageColor = isDark
        ? Colors.white.withValues(alpha: 0.78)
        : AppColors.textGrey.withValues(alpha: 0.94);

    return PopScope(
      canPop: !_isProcessing,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.16 : 0.58,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.28 : 0.10,
                            ),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                          BoxShadow(
                            color: confirmColor.withValues(
                              alpha: isDark ? 0.10 : 0.08,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: titleColor,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.message,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: messageColor,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 22),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stackButtons = constraints.maxWidth < 260;
                                final children = [
                                  Expanded(
                                    child: _DialogActionButton(
                                      label: widget.cancelLabel,
                                      onPressed: _isProcessing
                                          ? null
                                          : _handleCancel,
                                      isPrimary: false,
                                      tintColor: isDark
                                          ? Colors.white
                                          : AppColors.textGrey,
                                    ),
                                  ),
                                  if (!stackButtons) const SizedBox(width: 12),
                                  Expanded(
                                    child: _DialogActionButton(
                                      label: widget.confirmLabel,
                                      onPressed: _isProcessing
                                          ? null
                                          : _handleConfirm,
                                      isPrimary: true,
                                      tintColor: confirmColor,
                                      isLoading: _isProcessing,
                                    ),
                                  ),
                                ];

                                if (stackButtons) {
                                  return Column(
                                    children: [
                                      children[0],
                                      const SizedBox(height: 10),
                                      children[1],
                                    ],
                                  );
                                }
                                return Row(children: children);
                              },
                            ),
                          ],
                        ),
                      ),
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

class _PhraseConfirmationDialogRoute extends StatefulWidget {
  const _PhraseConfirmationDialogRoute({
    required this.parentContext,
    required this.title,
    required this.message,
    required this.confirmationPhrase,
    required this.inputLabel,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.isDestructive,
    required this.onConfirm,
    required this.errorMessage,
    required this.helperMessage,
  });

  final BuildContext parentContext;
  final String title;
  final String message;
  final String confirmationPhrase;
  final String inputLabel;
  final String cancelLabel;
  final String confirmLabel;
  final bool isDestructive;
  final Future<void> Function()? onConfirm;
  final String? errorMessage;
  final String? helperMessage;

  @override
  State<_PhraseConfirmationDialogRoute> createState() =>
      _PhraseConfirmationDialogRouteState();
}

class _PhraseConfirmationDialogRouteState
    extends State<_PhraseConfirmationDialogRoute> {
  late final TextEditingController _controller;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isMatch =>
      _controller.text.trim().toUpperCase() ==
      widget.confirmationPhrase.trim().toUpperCase();

  Future<void> _handleCancel() async {
    if (_isProcessing || !mounted) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _handleConfirm() async {
    if (_isProcessing || !_isMatch) return;
    if (widget.onConfirm == null) {
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _isProcessing = true);
    try {
      await widget.onConfirm!.call();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      final messengerContext = widget.parentContext;
      if (!messengerContext.mounted) return;
      AppSnackbar.error(
        messengerContext,
        message:
            widget.errorMessage ?? 'Something went wrong. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final confirmColor = widget.isDestructive
        ? const Color(0xFFE06A6A)
        : AppColors.primary;
    final surface = isDark ? const Color(0xCC1D1B1A) : const Color(0xCCFFFFFF);
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final messageColor = isDark
        ? Colors.white.withValues(alpha: 0.78)
        : AppColors.textGrey.withValues(alpha: 0.94);

    return PopScope(
      canPop: !_isProcessing,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.16 : 0.58,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.28 : 0.10,
                            ),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                          BoxShadow(
                            color: confirmColor.withValues(
                              alpha: isDark ? 0.10 : 0.08,
                            ),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: titleColor,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              widget.message,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: messageColor,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if ((widget.helperMessage ?? '')
                                .trim()
                                .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                widget.helperMessage!.trim(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: messageColor,
                                  height: 1.4,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            TextField(
                              controller: _controller,
                              textCapitalization: TextCapitalization.characters,
                              enabled: !_isProcessing,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: widget.inputLabel,
                                hintText: widget.confirmationPhrase,
                                filled: true,
                                fillColor: Colors.white.withValues(
                                  alpha: isDark ? 0.08 : 0.58,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: confirmColor.withValues(alpha: 0.18),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(
                                      alpha: isDark ? 0.12 : 0.68,
                                    ),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide(
                                    color: confirmColor.withValues(alpha: 0.75),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 22),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final stackButtons = constraints.maxWidth < 260;
                                final children = [
                                  Expanded(
                                    child: _DialogActionButton(
                                      label: widget.cancelLabel,
                                      onPressed: _isProcessing
                                          ? null
                                          : _handleCancel,
                                      isPrimary: false,
                                      tintColor: isDark
                                          ? Colors.white
                                          : AppColors.textGrey,
                                    ),
                                  ),
                                  if (!stackButtons) const SizedBox(width: 12),
                                  Expanded(
                                    child: _DialogActionButton(
                                      label: widget.confirmLabel,
                                      onPressed: (_isProcessing || !_isMatch)
                                          ? null
                                          : _handleConfirm,
                                      isPrimary: true,
                                      tintColor: confirmColor,
                                      isLoading: _isProcessing,
                                    ),
                                  ),
                                ];

                                if (stackButtons) {
                                  return Column(
                                    children: [
                                      children[0],
                                      const SizedBox(height: 10),
                                      children[1],
                                    ],
                                  );
                                }
                                return Row(children: children);
                              },
                            ),
                          ],
                        ),
                      ),
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

class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.label,
    required this.onPressed,
    required this.isPrimary,
    required this.tintColor,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final Color tintColor;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 52,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: isPrimary
                  ? tintColor.withValues(alpha: isDark ? 0.18 : 0.12)
                  : Colors.white.withValues(alpha: isDark ? 0.10 : 0.52),
              border: Border.all(
                color: tintColor.withValues(alpha: isDark ? 0.40 : 0.24),
              ),
            ),
            child: Center(
              child: isLoading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.1,
                        valueColor: AlwaysStoppedAnimation<Color>(tintColor),
                      ),
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: tintColor,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
