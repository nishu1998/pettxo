import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

enum AppButtonSize { regular, compact }

class AppButtonTokens {
  static double height(AppButtonSize size) => size == AppButtonSize.compact
      ? 42
      : 54;

  static double radius(AppButtonSize size) => size == AppButtonSize.compact
      ? 13
      : 16;

  static double iconSize(AppButtonSize size) => size == AppButtonSize.compact
      ? 16
      : 18;

  static double horizontalPadding(AppButtonSize size) =>
      size == AppButtonSize.compact ? 14 : 18;

  static double verticalPadding(AppButtonSize size) =>
      size == AppButtonSize.compact ? 9 : 14;

  static double fontSize(AppButtonSize size) => size == AppButtonSize.compact
      ? 13
      : 15;

  static TextStyle labelStyle(AppButtonSize size) => TextStyle(
    color: Colors.white,
    fontSize: fontSize(size),
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  static TextStyle secondaryLabelStyle(AppButtonSize size) => TextStyle(
    color: AppColors.primary,
    fontSize: fontSize(size),
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );
}

abstract class _BaseAnimatedButtonState<T extends StatefulWidget>
    extends State<T> {
  bool _pressed = false;

  void setPressed(bool value) {
    if (_pressed == value) return;
    setState(() {
      _pressed = value;
    });
  }

  bool get isPressed => _pressed;
}

class GradientButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final AppButtonSize size;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.size = AppButtonSize.regular,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends _BaseAnimatedButtonState<GradientButton> {
  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final radius = AppButtonTokens.radius(widget.size);

    Widget child = AnimatedScale(
      scale: isPressed && !disabled ? 0.98 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: disabled ? 0.5 : (isPressed ? 0.92 : 1),
        duration: const Duration(milliseconds: 120),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppColors.brandGradient,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              onTapDown: (_) => setPressed(true),
              onTapUp: (_) => setPressed(false),
              onTapCancel: () => setPressed(false),
              borderRadius: BorderRadius.circular(radius),
              splashColor: Colors.white.withValues(alpha: 0.14),
              highlightColor: Colors.white.withValues(alpha: 0.06),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: AppButtonTokens.height(widget.size),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppButtonTokens.horizontalPadding(widget.size),
                    vertical: AppButtonTokens.verticalPadding(widget.size),
                  ),
                  child: Center(
                    child: _ButtonLabel(
                      label: widget.label,
                      icon: widget.icon,
                      style: AppButtonTokens.labelStyle(widget.size),
                      iconColor: Colors.white,
                      iconSize: AppButtonTokens.iconSize(widget.size),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.expand) {
      child = SizedBox(width: double.infinity, child: child);
    }

    return child;
  }
}

class SecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;
  final AppButtonSize size;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
    this.size = AppButtonSize.regular,
  });

  @override
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends _BaseAnimatedButtonState<SecondaryButton> {
  @override
  Widget build(BuildContext context) {
    final disabled = widget.onPressed == null;
    final radius = AppButtonTokens.radius(widget.size);

    Widget child = AnimatedScale(
      scale: isPressed && !disabled ? 0.985 : 1,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: disabled ? 0.45 : 1,
        duration: const Duration(milliseconds: 120),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isPressed
                ? AppColors.primary.withValues(alpha: 0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: AppColors.primary.withValues(
                alpha: disabled ? 0.18 : 0.36,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              onTapDown: (_) => setPressed(true),
              onTapUp: (_) => setPressed(false),
              onTapCancel: () => setPressed(false),
              borderRadius: BorderRadius.circular(radius),
              splashColor: AppColors.primary.withValues(alpha: 0.08),
              highlightColor: AppColors.primary.withValues(alpha: 0.04),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: AppButtonTokens.height(widget.size),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppButtonTokens.horizontalPadding(widget.size),
                    vertical: AppButtonTokens.verticalPadding(widget.size),
                  ),
                  child: Center(
                    child: _ButtonLabel(
                      label: widget.label,
                      icon: widget.icon,
                      style: AppButtonTokens.secondaryLabelStyle(widget.size),
                      iconColor: AppColors.primary,
                      iconSize: AppButtonTokens.iconSize(widget.size),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.expand) {
      child = SizedBox(width: double.infinity, child: child);
    }

    return child;
  }
}

class _ButtonLabel extends StatelessWidget {
  final String label;
  final IconData? icon;
  final TextStyle style;
  final Color iconColor;
  final double iconSize;

  const _ButtonLabel({
    required this.label,
    required this.icon,
    required this.style,
    required this.iconColor,
    required this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return Text(label, textAlign: TextAlign.center, style: style);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: iconSize, color: iconColor),
        const SizedBox(width: 8),
        Flexible(child: Text(label, textAlign: TextAlign.center, style: style)),
      ],
    );
  }
}
