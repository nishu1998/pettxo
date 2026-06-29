import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class LegalConsentSegment {
  final String text;
  final VoidCallback? onTap;

  const LegalConsentSegment({
    required this.text,
    this.onTap,
  });
}

class LegalConsentCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final List<LegalConsentSegment> segments;
  final String? errorText;

  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.segments,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: AppColors.primary,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(
                  children: [
                    for (final segment in segments)
                      segment.onTap == null
                          ? Text(
                              segment.text,
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontSize: 14,
                                height: 1.45,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : InkWell(
                              onTap: segment.onTap,
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 1,
                                ),
                                child: Text(
                                  segment.text,
                                  style: const TextStyle(
                                    color: Color(0xFF2563EB),
                                    fontSize: 14,
                                    height: 1.45,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              errorText!,
              style: const TextStyle(
                color: Color(0xFFC94B4B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
