import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class DetailRowData {
  final String label;
  final String value;
  final Color? valueColor;
  final FontWeight? valueWeight;
  final Widget? trailing;

  const DetailRowData({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueWeight,
    this.trailing,
  });
}

class SectionBlock extends StatelessWidget {
  final String title;
  final List<DetailRowData>? rows;
  final Widget? child;
  final Color backgroundColor;
  final Color borderColor;

  const SectionBlock({
    super.key,
    required this.title,
    this.rows,
    this.child,
    this.backgroundColor = Colors.white,
    this.borderColor = const Color(0x1A000000),
  });

  List<Widget> _childWidgets() {
    if (child == null) return const [];
    return [child!];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          if ((rows?.isNotEmpty ?? false) || child != null)
            const SizedBox(height: 12),
          if (rows != null)
            ...rows!.map((row) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    row.trailing ??
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180),
                          child: Text(
                            row.value,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: row.valueColor ?? AppColors.textDark,
                              fontSize: 13,
                              fontWeight: row.valueWeight ?? FontWeight.w600,
                            ),
                          ),
                        ),
                  ],
                ),
              );
            }),
          ..._childWidgets(),
        ],
      ),
    );
  }
}
