import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class ProfileTypeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final String badge;

  const ProfileTypeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    required this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 380;

    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(compact ? 20 : 22),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
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
                child: Icon(icon, color: Colors.white, size: compact ? 24 : 26),
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
                        badge,
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
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 16.5 : 17,
                        color: AppColors.textDark,
                      ),
                    ),
                    SizedBox(height: compact ? 4 : 5),
                    Text(
                      description,
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
                width: compact ? 34 : 36,
                height: compact ? 34 : 36,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(compact ? 12 : 13),
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.textDark,
                  size: compact ? 18 : 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
