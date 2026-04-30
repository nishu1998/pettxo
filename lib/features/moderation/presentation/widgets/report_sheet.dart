import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/repositories/report_repository.dart';

class ReportSheet {
  static const List<String> reasonOptions = [
    'Spam',
    'Fake information',
    'Abusive or harmful',
    'Inappropriate content',
    'Safety concern',
    'Other',
  ];

  static Future<void> show({
    required BuildContext context,
    required String type,
    required String targetId,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      AppSnackbar.showWarning(context, 'Please sign in to submit a report.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _ReportSheetView(type: type, targetId: targetId);
      },
    );
  }
}

class _ReportSheetView extends StatefulWidget {
  final String type;
  final String targetId;

  const _ReportSheetView({required this.type, required this.targetId});

  @override
  State<_ReportSheetView> createState() => _ReportSheetViewState();
}

class _ReportSheetViewState extends State<_ReportSheetView> {
  final ReportRepository _reportRepository = ReportRepository();
  final TextEditingController _descriptionController = TextEditingController();
  String? _selectedReason;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _selectedReason?.trim() ?? '';
    if (_isSubmitting || reason.isEmpty) return;

    setState(() => _isSubmitting = true);
    try {
      await _reportRepository.createReport(
        type: widget.type,
        targetId: widget.targetId,
        reason: reason,
        description: _descriptionController.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      AppSnackbar.showSuccess(
        context,
        'Report submitted. Our team will review it.',
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        'We could not submit your report right now.',
      );
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: BoxDecoration(
            color: const Color(0xFFFCF8F5),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Report',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tell us what feels wrong so our team can review it.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                ...ReportSheet.reasonOptions.map((reason) {
                  final isSelected = _selectedReason == reason;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: _isSubmitting
                          ? null
                          : () => setState(() => _selectedReason = reason),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFFF1EA)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.24)
                                : AppColors.primary.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                reason,
                                style: TextStyle(
                                  color: AppColors.textDark,
                                  fontSize: 14.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                ),
                              ),
                            ),
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textGrey,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: TextField(
                    controller: _descriptionController,
                    enabled: !_isSubmitting,
                    maxLines: 4,
                    minLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Add more details (optional)',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: EdgeInsets.only(bottom: safeBottom),
                  child: GradientButton(
                    label: _isSubmitting ? 'Submitting...' : 'Submit Report',
                    onPressed: _selectedReason == null || _isSubmitting
                        ? null
                        : _submit,
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
