import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_glass_overlay.dart';
import '../../domain/models/profile_type.dart';

class ProfileTypeSelectorDialog {
  ProfileTypeSelectorDialog._();

  static Future<ProfileType?> show(
    BuildContext context, {
    required ProfileType selectedType,
  }) {
    return showGeneralDialog<ProfileType>(
      context: context,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.16),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) {
        return _ProfileTypeSelectorSheet(selectedType: selectedType);
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

class _ProfileTypeSelectorSheet extends StatelessWidget {
  const _ProfileTypeSelectorSheet({required this.selectedType});

  final ProfileType selectedType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: AppGlassDialogFrame(
              maxWidth: 430,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              borderRadius: BorderRadius.circular(26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Account Type',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: isDark ? Colors.white : AppColors.textDark,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose the tag that best describes how you identify on Pettxo.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.76)
                          : AppColors.textGrey,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final type in ProfileType.values) ...[
                    _ProfileTypeOptionTile(
                      type: type,
                      isSelected: type == selectedType,
                      onTap: () => Navigator.of(context).pop(type),
                    ),
                    if (type != ProfileType.values.last)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTypeOptionTile extends StatelessWidget {
  const _ProfileTypeOptionTile({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  final ProfileType type;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 20 : 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.68),
            borderRadius: BorderRadius.circular(compact ? 20 : 22),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.50)
                  : AppColors.primary.withValues(alpha: 0.08),
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: compact ? 18 : 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 16),
            child: Row(
              children: [
                Container(
                  width: compact ? 50 : 54,
                  height: compact ? 50 : 54,
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradientDiagonal,
                    borderRadius: BorderRadius.circular(compact ? 15 : 16),
                  ),
                  child: Icon(
                    type.icon,
                    color: Colors.white,
                    size: compact ? 24 : 26,
                  ),
                ),
                SizedBox(width: compact ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 9 : 10,
                          vertical: compact ? 4 : 5,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4EE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          type.badge,
                          style: TextStyle(
                            fontSize: compact ? 10 : 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 7 : 8),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 16.5 : 17,
                          color: AppColors.textDark,
                        ),
                      ),
                      SizedBox(height: compact ? 4 : 5),
                      Text(
                        type.description,
                        style: TextStyle(
                          color: AppColors.textGrey,
                          height: 1.35,
                          fontSize: compact ? 13 : 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: compact ? 10 : 12),
                Container(
                  width: compact ? 28 : 30,
                  height: compact ? 28 : 30,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.14)
                        : Colors.white.withValues(alpha: 0.74),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.28)
                          : Colors.white.withValues(alpha: 0.80),
                    ),
                  ),
                  child: Icon(
                    isSelected ? Icons.check_rounded : Icons.circle_outlined,
                    color: isSelected ? AppColors.primary : AppColors.textGrey,
                    size: compact ? 17 : 18,
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
