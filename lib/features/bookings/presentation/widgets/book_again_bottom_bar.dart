import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class BookAgainBottomBar extends StatelessWidget {
  const BookAgainBottomBar({
    super.key,
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Container(
          key: const ValueKey('book-again-cta-shell'),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: SizedBox(
            height: 54,
            child: AnimatedOpacity(
              opacity: isLoading ? 0.5 : 1,
              duration: const Duration(milliseconds: 120),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('book-again-cta'),
                    onTap: isLoading ? null : onPressed,
                    borderRadius: BorderRadius.circular(19),
                    child: Center(
                      child: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.event_repeat_outlined,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Book Again',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                  ),
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
    );
  }
}
