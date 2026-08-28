import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'pettxo_loading_animation.dart';

enum PettxoFullScreenLoaderMode { frosted, opaque }

class PettxoFullScreenLoader extends StatelessWidget {
  const PettxoFullScreenLoader({
    super.key,
    required this.message,
    this.animationController,
    this.mode = PettxoFullScreenLoaderMode.frosted,
  });

  final String message;
  final AnimationController? animationController;
  final PettxoFullScreenLoaderMode mode;

  @override
  Widget build(BuildContext context) {
    final creamOverlay = AppColors.background.withValues(alpha: 0.68);
    final warmGlow = AppColors.primary.withValues(alpha: 0.10);
    final isOpaque = mode == PettxoFullScreenLoaderMode.opaque;

    return Positioned.fill(
      child: Material(
        color: isOpaque ? AppColors.background : Colors.transparent,
        child: Stack(
          children: [
            ModalBarrier(
              dismissible: false,
              color: isOpaque ? AppColors.background : Colors.transparent,
            ),
            Positioned(
              top: -110,
              left: -60,
              child: IgnorePointer(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: warmGlow,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -90,
              bottom: 40,
              child: IgnorePointer(
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: isOpaque
                  ? const ColoredBox(color: AppColors.background)
                  : ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: ColoredBox(color: creamOverlay),
                      ),
                    ),
            ),
            SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: PettxoLoadingAnimation(
                      controller: animationController,
                      message: message,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
