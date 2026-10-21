import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../widgets/pettxo_loading_animation.dart';
import 'app_update_service.dart';

class MandatoryUpdateScreen extends StatelessWidget {
  const MandatoryUpdateScreen({
    super.key,
    required this.message,
    required this.isUpdating,
    required this.onUpdate,
    required this.onRetry,
    this.lastResult,
  });

  final String message;
  final bool isUpdating;
  final VoidCallback onUpdate;
  final VoidCallback onRetry;
  final MandatoryUpdateActionResult? lastResult;

  bool get _showFailure =>
      lastResult == MandatoryUpdateActionResult.canceled ||
      lastResult == MandatoryUpdateActionResult.failed ||
      lastResult == MandatoryUpdateActionResult.storeFailed ||
      lastResult == MandatoryUpdateActionResult.noUpdateAvailable;

  @override
  Widget build(BuildContext context) {
    const updateColor = Color(0xFFFFB067);
    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 44,
                maxWidth: 520,
              ),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        color: updateColor.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.pets_rounded,
                        size: 52,
                        color: AppColors.textDark,
                        semanticLabel: 'Pettxo update',
                      ),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'A Better Pettxo Awaits!',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        height: 1.5,
                        color: AppColors.textGrey,
                      ),
                    ),
                    if (_showFailure) ...[
                      const SizedBox(height: 14),
                      Text(
                        'The update could not be completed. Please try again or open Google Play.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: Semantics(
                        button: true,
                        label: 'Update Pettxo Now',
                        child: FilledButton(
                          onPressed: isUpdating ? null : onUpdate,
                          style: FilledButton.styleFrom(
                            backgroundColor: updateColor,
                            foregroundColor: AppColors.textDark,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: isUpdating
                              ? const SizedBox.square(
                                  dimension: 28,
                                  child: PettxoLoader.compact(
                                    size: 28,
                                    semanticLabel: 'Opening update',
                                  ),
                                )
                              : const Text(
                                  'Update Pettxo Now',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                        ),
                      ),
                    ),
                    if (_showFailure)
                      TextButton(
                        onPressed: isUpdating ? null : onRetry,
                        child: const Text('Retry'),
                      ),
                    const Spacer(),
                    const SizedBox(height: 24),
                    Text(
                      'This update is required to continue using Pettxo.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w600,
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
