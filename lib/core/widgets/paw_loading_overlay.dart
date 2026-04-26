import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class PawLoadingOverlay extends StatefulWidget {
  final ValueListenable<String?> messageListenable;

  const PawLoadingOverlay({super.key, required this.messageListenable});

  @override
  State<PawLoadingOverlay> createState() => _PawLoadingOverlayState();
}

class _PawLoadingOverlayState extends State<PawLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          ModalBarrier(
            dismissible: false,
            color: const Color(0xFF2D211A).withValues(alpha: 0.18),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return SizedBox(
                        width: 160,
                        height: 90,
                        child: Stack(
                          alignment: Alignment.center,
                          children: List.generate(5, (index) {
                            return _AnimatedPaw(
                              progress: _controller.value,
                              delay: index * 0.14,
                              verticalShift: (index.isEven ? -1 : 1) * 8.0,
                              size: 18 + (index % 2) * 2.0,
                            );
                          }),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  ValueListenableBuilder<String?>(
                    valueListenable: widget.messageListenable,
                    builder: (context, message, child) {
                      final resolvedMessage =
                          message == null || message.trim().isEmpty
                          ? 'Fetching a few pet-friendly details...'
                          : message;

                      return Text(
                        resolvedMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.45,
                          shadows: [
                            Shadow(
                              color: Color(0x33000000),
                              blurRadius: 10,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedPaw extends StatelessWidget {
  final double progress;
  final double delay;
  final double verticalShift;
  final double size;

  const _AnimatedPaw({
    required this.progress,
    required this.delay,
    required this.verticalShift,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final phase = (progress - delay + 1) % 1;
    final eased = Curves.easeInOut.transform(math.min(phase / 0.72, 1));
    final isVisible = phase <= 0.72;
    final opacity = isVisible
        ? (math.sin(eased * math.pi).clamp(0, 1) * 0.92).toDouble()
        : 0.0;
    final scale = 0.88 + (eased * 0.22);
    final dx = -46 + (eased * 92);
    final dy = verticalShift + (math.sin((eased * math.pi) + delay) * 4.5);

    return Positioned(
      left: 80 + dx - (size / 2),
      top: 38 + dy - (size / 2),
      child: Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: math.pi / 2,
          child: Transform.scale(
            scale: scale,
            child: Icon(
              Icons.pets_rounded,
              color: AppColors.primary,
              size: size,
            ),
          ),
        ),
      ),
    );
  }
}
