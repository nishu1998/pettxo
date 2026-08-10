import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../services/play_store_review_service.dart';
import 'app_buttons.dart';

class PlayStoreReviewDialog {
  PlayStoreReviewDialog._();

  static Future<PlayStoreReviewDialogAction?> show({
    required BuildContext context,
  }) {
    return showGeneralDialog<PlayStoreReviewDialogAction>(
      context: context,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.54),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, _) => const _PlayStoreReviewDialogBody(),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

class _PlayStoreReviewDialogBody extends StatefulWidget {
  const _PlayStoreReviewDialogBody();

  @override
  State<_PlayStoreReviewDialogBody> createState() =>
      _PlayStoreReviewDialogBodyState();
}

class _PlayStoreReviewDialogBodyState
    extends State<_PlayStoreReviewDialogBody> {
  bool _isSubmitting = false;

  void _close(PlayStoreReviewDialogAction action) {
    if (!mounted) return;
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 30,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: -18,
                      bottom: 16,
                      child: Icon(
                        Icons.pets_rounded,
                        size: 48,
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                    ),
                    Positioned(
                      right: -10,
                      bottom: 42,
                      child: Icon(
                        Icons.pets_rounded,
                        size: 40,
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: Semantics(
                                label: 'Close',
                                button: true,
                                child: InkWell(
                                  onTap: _isSubmitting
                                      ? null
                                      : () => _close(
                                          PlayStoreReviewDialogAction.close,
                                        ),
                                  borderRadius: BorderRadius.circular(18),
                                  child: Ink(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFDF5EF),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.14,
                                        ),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.04,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      color: AppColors.textDark,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Image.asset(
                              'assets/images/review/pettxo_review_pets.png',
                              width: 152,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 152,
                                  height: 116,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF2EA),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.pets_rounded,
                                    color: AppColors.primary.withValues(
                                      alpha: 0.82,
                                    ),
                                    size: 52,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Enjoying Pettxo? ❤️',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: AppColors.textDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 28,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'If you love using Pettxo, would you mind rating us on the Play Store?',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: AppColors.textGrey,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 22),
                            const _FeatureStrip(),
                            const SizedBox(height: 22),
                            GradientButton(
                              label: 'Rate us on Play Store',
                              icon: Icons.star_rounded,
                              onPressed: _isSubmitting
                                  ? null
                                  : () {
                                      setState(() => _isSubmitting = true);
                                      _close(
                                        PlayStoreReviewDialogAction
                                            .rateOnPlayStore,
                                      );
                                    },
                            ),
                            const SizedBox(height: 12),
                            SecondaryButton(
                              label: 'Maybe Later',
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _close(
                                      PlayStoreReviewDialogAction.maybeLater,
                                    ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _isSubmitting
                                  ? null
                                  : () => _close(
                                      PlayStoreReviewDialogAction.noThanks,
                                    ),
                              child: Text(
                                'No Thanks',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: AppColors.textGrey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureStrip extends StatelessWidget {
  const _FeatureStrip();

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppColors.textDark,
      fontWeight: FontWeight.w600,
      height: 1.35,
    );

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3EB),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      child: Row(
        children: [
          _FeatureStripItem(
            icon: Icons.pets_rounded,
            label: 'Trusted pet\nservices',
            textStyle: textStyle,
          ),
          _FeatureDivider(),
          _FeatureStripItem(
            icon: Icons.groups_rounded,
            label: 'Amazing pet\ncommunity',
            textStyle: textStyle,
          ),
          _FeatureDivider(),
          _FeatureStripItem(
            icon: Icons.verified_user_rounded,
            label: 'Better experience\nfor pet lovers',
            textStyle: textStyle,
          ),
        ],
      ),
    );
  }
}

class _FeatureStripItem extends StatelessWidget {
  const _FeatureStripItem({
    required this.icon,
    required this.label,
    required this.textStyle,
  });

  final IconData icon;
  final String label;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, style: textStyle),
        ],
      ),
    );
  }
}

class _FeatureDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 58,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.primary.withValues(alpha: 0.14),
    );
  }
}
