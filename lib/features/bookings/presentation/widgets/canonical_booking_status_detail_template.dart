import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';

class StatusPresentationModel {
  const StatusPresentationModel({
    required this.summaryRows,
    required this.status,
    required this.timeline,
    required this.financialRows,
    required this.importantInformation,
    required this.actions,
  });

  final List<StatusSummaryRowModel> summaryRows;
  final StatusCardPresentationModel status;
  final List<BookingTimelineStepModel> timeline;
  final List<StatusFinancialRowModel> financialRows;
  final StatusImportantInformationModel importantInformation;
  final StatusActionsPresentationModel actions;
}

class StatusSummaryRowModel {
  const StatusSummaryRowModel({
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;
}

class StatusCardPresentationModel {
  const StatusCardPresentationModel({
    required this.icon,
    required this.title,
    required this.explanation,
    required this.accentColor,
    this.badgeLabel,
  });

  final IconData icon;
  final String title;
  final String explanation;
  final Color accentColor;
  final String? badgeLabel;
}

class BookingTimelineStepModel {
  const BookingTimelineStepModel({
    required this.label,
    this.subtitle,
    this.timestamp,
    this.isHighlighted = false,
    this.tone = BookingTimelineStepTone.success,
  });

  final String label;
  final String? subtitle;
  final String? timestamp;
  final bool isHighlighted;
  final BookingTimelineStepTone tone;
}

enum BookingTimelineStepTone { success, warning, failure, neutral }

class StatusFinancialRowModel {
  const StatusFinancialRowModel({
    required this.label,
    required this.value,
    this.isEmphasized = false,
    this.valueTone = StatusFinancialValueTone.standard,
  });

  final String label;
  final String value;
  final bool isEmphasized;
  final StatusFinancialValueTone valueTone;
}

enum StatusFinancialValueTone { standard, positive, warning, danger, neutral }

class StatusImportantInformationModel {
  const StatusImportantInformationModel({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

class StatusActionsPresentationModel {
  const StatusActionsPresentationModel({
    this.primaryLabel,
    this.onPrimaryPressed,
    this.primaryIcon,
    this.secondaryLabel,
    this.onSecondaryPressed,
    this.secondaryIcon,
    this.footnote,
  });

  final String? primaryLabel;
  final VoidCallback? onPrimaryPressed;
  final IconData? primaryIcon;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryPressed;
  final IconData? secondaryIcon;
  final String? footnote;
}

class CanonicalBookingStatusDetailTopBar extends StatelessWidget
    implements PreferredSizeWidget {
  const CanonicalBookingStatusDetailTopBar({
    super.key,
    this.title = 'Booking Details',
  });

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(92);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CanonicalBookingStatusDetailTemplate extends StatelessWidget {
  const CanonicalBookingStatusDetailTemplate({super.key, required this.model});

  final StatusPresentationModel model;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        const BookingDetailsSectionLabel('Booking summary'),
        const SizedBox(height: 10),
        BookingSummaryCard(rows: model.summaryRows),
        const SizedBox(height: 16),
        const BookingDetailsSectionLabel('Booking status'),
        const SizedBox(height: 10),
        BookingStatusCard(model: model.status),
        const SizedBox(height: 16),
        const BookingDetailsSectionLabel('Booking timeline'),
        const SizedBox(height: 10),
        BookingTimelineCard(steps: model.timeline),
        const SizedBox(height: 16),
        const BookingDetailsSectionLabel('Financial summary'),
        const SizedBox(height: 10),
        FinancialSummaryCard(rows: model.financialRows),
        const SizedBox(height: 16),
        const BookingDetailsSectionLabel('Important information'),
        const SizedBox(height: 10),
        ImportantInformationCard(model: model.importantInformation),
        const SizedBox(height: 16),
        const BookingDetailsSectionLabel('Primary actions'),
        const SizedBox(height: 10),
        BookingActionsCard(model: model.actions),
      ],
    );
  }
}

class BookingSummaryCard extends StatelessWidget {
  const BookingSummaryCard({super.key, required this.rows});

  final List<StatusSummaryRowModel> rows;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            _TwoColumnRow(
              label: rows[index].label,
              value: rows[index].value,
              labelIcon: rows[index].icon,
            ),
            if (index != rows.length - 1) const _HairlineDivider(),
          ],
        ],
      ),
    );
  }
}

class BookingStatusCard extends StatelessWidget {
  const BookingStatusCard({super.key, required this.model});

  final StatusCardPresentationModel model;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      backgroundColor: model.accentColor.withValues(alpha: 0.08),
      borderColor: model.accentColor.withValues(alpha: 0.12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (model.badgeLabel != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: model.accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                model.badgeLabel!,
                style: TextStyle(
                  color: model.accentColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookingDetailsIconTile(
                icon: model.icon,
                iconColor: model.accentColor,
                backgroundColor: model.accentColor.withValues(alpha: 0.14),
                size: 60,
                iconSize: 30,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.title,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        model.explanation,
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BookingTimelineCard extends StatelessWidget {
  const BookingTimelineCard({super.key, required this.steps});

  final List<BookingTimelineStepModel> steps;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        children: [
          for (var index = 0; index < steps.length; index++)
            _TimelineStepTile(
              step: steps[index],
              isLast: index == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class FinancialSummaryCard extends StatelessWidget {
  const FinancialSummaryCard({super.key, required this.rows});

  final List<StatusFinancialRowModel> rows;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            _FinancialRowTile(row: rows[index]),
            if (index != rows.length - 1) const _HairlineDivider(),
          ],
        ],
      ),
    );
  }
}

class ImportantInformationCard extends StatelessWidget {
  const ImportantInformationCard({super.key, required this.model});

  final StatusImportantInformationModel model;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      backgroundColor: const Color(0xFFF8FBFF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BookingDetailsIconTile(
                icon: Icons.info_outline_rounded,
                iconColor: Color(0xFF2D6CDF),
                backgroundColor: Color(0xFFE6F0FF),
                size: 30,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  model.title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            model.body,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class BookingActionsCard extends StatelessWidget {
  const BookingActionsCard({super.key, required this.model});

  final StatusActionsPresentationModel model;

  @override
  Widget build(BuildContext context) {
    return BookingDetailsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (model.footnote != null) ...[
            Text(
              model.footnote!,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (model.primaryLabel != null)
            SecondaryButton(
              label: model.primaryLabel!,
              onPressed: model.onPrimaryPressed,
              icon: model.primaryIcon,
            ),
          if (model.secondaryLabel != null) ...[
            if (model.primaryLabel != null) const SizedBox(height: 10),
            SecondaryButton(
              label: model.secondaryLabel!,
              onPressed: model.onSecondaryPressed,
              icon: model.secondaryIcon,
            ),
          ],
          if (model.primaryLabel == null && model.secondaryLabel == null)
            const Text(
              'No actions are required for this booking right now.',
              style: TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
        ],
      ),
    );
  }
}

class _TimelineStepTile extends StatelessWidget {
  const _TimelineStepTile({required this.step, required this.isLast});

  final BookingTimelineStepModel step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final iconColor = switch (step.tone) {
      BookingTimelineStepTone.success => const Color(0xFF16A34A),
      BookingTimelineStepTone.warning => const Color(0xFFF97316),
      BookingTimelineStepTone.failure => const Color(0xFFDC2626),
      BookingTimelineStepTone.neutral => AppColors.textGrey.withValues(
        alpha: 0.65,
      ),
    };
    final tileColor = iconColor.withValues(alpha: 0.12);
    final icon = switch (step.tone) {
      BookingTimelineStepTone.success => Icons.check_rounded,
      BookingTimelineStepTone.warning => Icons.schedule_rounded,
      BookingTimelineStepTone.failure => Icons.close_rounded,
      BookingTimelineStepTone.neutral => Icons.circle,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                BookingDetailsIconTile(
                  icon: icon,
                  iconColor: iconColor,
                  backgroundColor: tileColor,
                  size: 24,
                  iconSize: 14,
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 42,
                    margin: const EdgeInsets.only(top: 4),
                    color: iconColor.withValues(alpha: 0.28),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      color: AppColors.textDark,
                      fontSize: 16,
                      fontWeight: step.isHighlighted
                          ? FontWeight.w900
                          : FontWeight.w800,
                    ),
                  ),
                  if (step.timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      step.timestamp!,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (step.subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      step.subtitle!,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinancialRowTile extends StatelessWidget {
  const _FinancialRowTile({required this.row});

  final StatusFinancialRowModel row;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: row.isEmphasized ? AppColors.textDark : AppColors.textGrey,
      fontSize: row.isEmphasized ? 17 : 16,
      fontWeight: row.isEmphasized ? FontWeight.w900 : FontWeight.w800,
    );
    final valueColor = switch (row.valueTone) {
      StatusFinancialValueTone.positive => const Color(0xFF16A34A),
      StatusFinancialValueTone.warning => const Color(0xFFF97316),
      StatusFinancialValueTone.danger => const Color(0xFFDC2626),
      StatusFinancialValueTone.neutral => AppColors.textGrey,
      StatusFinancialValueTone.standard =>
        row.isEmphasized ? AppColors.primary : AppColors.textDark,
    };
    final shouldChip =
        row.valueTone != StatusFinancialValueTone.standard &&
        row.valueTone != StatusFinancialValueTone.neutral;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(row.label, style: labelStyle)),
          const SizedBox(width: 12),
          shouldChip
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: valueColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: valueColor.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    row.value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: valueColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                )
              : Text(
                  row.value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: valueColor,
                    fontSize: row.isEmphasized ? 17 : 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ],
      ),
    );
  }
}

class _TwoColumnRow extends StatelessWidget {
  const _TwoColumnRow({
    required this.label,
    required this.value,
    this.labelIcon,
  });

  final String label;
  final String value;
  final IconData? labelIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (labelIcon != null) ...[
            BookingDetailsIconTile(
              icon: labelIcon!,
              iconColor: AppColors.textGrey,
              backgroundColor: AppColors.textGrey.withValues(alpha: 0.10),
              size: 28,
              iconSize: 16,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.fade,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BookingDetailsIconTile extends StatelessWidget {
  const BookingDetailsIconTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    this.size = 28,
    this.iconSize = 16,
  });

  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: iconColor, size: iconSize),
    );
  }
}

class _HairlineDivider extends StatelessWidget {
  const _HairlineDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: AppColors.textGrey.withValues(alpha: 0.12),
    );
  }
}

class BookingDetailsSurfaceCard extends StatelessWidget {
  const BookingDetailsSurfaceCard({
    super.key,
    required this.child,
    this.backgroundColor = Colors.white,
    this.borderColor,
  });

  final Widget child;
  final Color backgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: borderColor ?? AppColors.primary.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class BookingDetailsSectionLabel extends StatelessWidget {
  const BookingDetailsSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: AppColors.textGrey,
        letterSpacing: 1.6,
        fontWeight: FontWeight.w900,
        fontSize: 14,
      ),
    );
  }
}
