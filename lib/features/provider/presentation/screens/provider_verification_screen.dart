import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../data/repositories/provider_onboarding_repository.dart';
import '../../domain/models/provider_onboarding_models.dart';

class ProviderVerificationScreen extends StatefulWidget {
  const ProviderVerificationScreen({super.key});

  @override
  State<ProviderVerificationScreen> createState() =>
      _ProviderVerificationScreenState();
}

class _ProviderVerificationScreenState
    extends State<ProviderVerificationScreen> {
  final ProviderOnboardingRepository _repository =
      ProviderOnboardingRepository();
  final ImagePicker _imagePicker = ImagePicker();

  ProviderVerificationRecord? _verification;
  String _selectedDocumentType = 'aadhaar';
  File? _frontImage;
  File? _backImage;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final verification = await _repository.fetchCurrentVerification();
      if (!mounted) return;
      setState(() {
        _verification = verification;
        if (verification.documentType.isNotEmpty) {
          _selectedDocumentType = verification.documentType;
        }
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'We could not load your provider verification right now.';
      });
    }
  }

  Future<void> _pickImage({required bool isFront}) async {
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (!mounted || file == null) return;
    setState(() {
      if (isFront) {
        _frontImage = File(file.path);
      } else {
        _backImage = File(file.path);
      }
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (_frontImage == null) {
      AppFeedback.show(
        context,
        message: 'Upload the front side of your identity proof first.',
        tone: AppFeedbackTone.info,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _repository.submitVerification(
        documentType: _selectedDocumentType,
        frontImage: _frontImage!,
        backImage: _backImage,
      );
      if (!mounted) return;
      AppFeedback.show(
        context,
        message:
            'Your verification is under review. This usually takes 24–72 hours.',
        tone: AppFeedbackTone.success,
      );
      Navigator.pop(context, true);
    } on FirebaseException catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: _friendlyVerificationError(error),
        tone: AppFeedbackTone.error,
      );
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not submit your verification right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _friendlyVerificationError(FirebaseException error) {
    final message = (error.message ?? '').toLowerCase();
    if (error.code == 'unauthorized' || message.contains('permission denied')) {
      return 'Verification upload was blocked by storage permissions. Please try again after updating the app, or contact support if it keeps happening.';
    }
    if (error.code == 'canceled') {
      return 'The upload was interrupted. Please try again.';
    }
    if (message.contains('object does not exist')) {
      return 'The verification upload path is unavailable right now. Please try again.';
    }
    return 'We could not submit your verification right now.';
  }

  @override
  Widget build(BuildContext context) {
    final verification = _verification;
    final canResubmit =
        verification == null ||
        verification.status == providerVerificationNotSubmitted ||
        verification.status == providerVerificationRejected;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Provider Verification'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _ErrorState(message: _loadError!, onRetry: _load)
          : ListView(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 24 + bottomInset),
              children: [
                _InfoCard(
                  title: 'Why this is needed',
                  subtitle:
                      'To protect pets and pet parents, we verify every provider before long-term discovery and booking access. Approval usually takes 24–72 hours.',
                ),
                const SizedBox(height: 16),
                _StatusCard(verification: verification!),
                const SizedBox(height: 16),
                _FormCard(
                  enabled: canResubmit,
                  selectedDocumentType: _selectedDocumentType,
                  onDocumentTypeChanged: (value) {
                    setState(() => _selectedDocumentType = value);
                  },
                  frontImage: _frontImage,
                  backImage: _backImage,
                  onPickFront: () => _pickImage(isFront: true),
                  onPickBack: () => _pickImage(isFront: false),
                  existingFrontUrl: verification.documentFrontUrl,
                  existingBackUrl: verification.documentBackUrl,
                ),
                const SizedBox(height: 18),
                GradientButton(
                  label: verification.isRejected
                      ? 'Resubmit Documents'
                      : 'Submit Verification',
                  onPressed: canResubmit && !_isSubmitting ? _submit : null,
                ),
              ],
            ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _InfoCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.textGrey, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final ProviderVerificationRecord verification;

  const _StatusCard({required this.verification});

  @override
  Widget build(BuildContext context) {
    final toneColor = verification.isApproved
        ? const Color(0xFF177B4D)
        : verification.isRejected
        ? const Color(0xFFC94B4B)
        : verification.isPending
        ? AppColors.primary
        : AppColors.textGrey;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: toneColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: toneColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  verification.status == providerVerificationNotSubmitted
                      ? 'Not submitted'
                      : verification.status[0].toUpperCase() +
                            verification.status.substring(1),
                  style: TextStyle(
                    color: toneColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            verification.statusMessage,
            style: const TextStyle(color: AppColors.textDark, height: 1.45),
          ),
          if (verification.rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Reason: ${verification.rejectionReason}',
              style: const TextStyle(color: AppColors.textGrey, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  final bool enabled;
  final String selectedDocumentType;
  final ValueChanged<String> onDocumentTypeChanged;
  final File? frontImage;
  final File? backImage;
  final VoidCallback onPickFront;
  final VoidCallback onPickBack;
  final String existingFrontUrl;
  final String existingBackUrl;

  const _FormCard({
    required this.enabled,
    required this.selectedDocumentType,
    required this.onDocumentTypeChanged,
    required this.frontImage,
    required this.backImage,
    required this.onPickFront,
    required this.onPickBack,
    required this.existingFrontUrl,
    required this.existingBackUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Identity proof',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 14),
          _DocumentTypePicker(
            value: selectedDocumentType,
            enabled: enabled,
            onChanged: onDocumentTypeChanged,
          ),
          const SizedBox(height: 16),
          _UploadRow(
            title: 'Front image',
            subtitle: frontImage == null && existingFrontUrl.isNotEmpty
                ? 'A document image is already on file.'
                : 'Upload a clear photo of the front side.',
            hasImage: frontImage != null || existingFrontUrl.isNotEmpty,
            onTap: enabled ? onPickFront : null,
          ),
          const SizedBox(height: 12),
          _UploadRow(
            title: 'Back image (optional)',
            subtitle: backImage == null && existingBackUrl.isNotEmpty
                ? 'A back image is already on file.'
                : 'Add the back side if your document includes important details there.',
            hasImage: backImage != null || existingBackUrl.isNotEmpty,
            onTap: enabled ? onPickBack : null,
          ),
        ],
      ),
    );
  }
}

class _DocumentTypePicker extends StatelessWidget {
  const _DocumentTypePicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  static const _options = <({String value, String label, IconData icon})>[
    (value: 'aadhaar', label: 'Aadhaar Card', icon: Icons.badge_outlined),
    (
      value: 'drivingLicense',
      label: 'Driving License',
      icon: Icons.directions_car_filled_outlined,
    ),
    (value: 'voterId', label: 'Voter ID', icon: Icons.how_to_vote_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final selected = _options.firstWhere(
      (option) => option.value == value,
      orElse: () => _options.first,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: !enabled
          ? null
          : () async {
              final nextValue = await showModalBottomSheet<String>(
                context: context,
                backgroundColor: Colors.transparent,
                builder: (context) => _DocumentTypeSheet(currentValue: value),
              );
              if (nextValue != null) {
                onChanged(nextValue);
              }
            },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFAF7),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: enabled
                ? AppColors.primary.withValues(alpha: 0.14)
                : AppColors.textGrey.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(selected.icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Document type',
                    style: TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selected.label,
                    style: TextStyle(
                      color: enabled ? AppColors.textDark : AppColors.textGrey,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: enabled ? AppColors.primary : AppColors.textGrey,
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTypeSheet extends StatelessWidget {
  const _DocumentTypeSheet({required this.currentValue});

  final String currentValue;

  @override
  Widget build(BuildContext context) {
    const options = _DocumentTypePicker._options;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.textGrey.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Choose document type',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select the identity proof you want to upload for verification.',
              style: TextStyle(color: AppColors.textGrey, height: 1.45),
            ),
            const SizedBox(height: 16),
            for (final option in options) ...[
              _DocumentTypeTile(
                icon: option.icon,
                label: option.label,
                selected: option.value == currentValue,
                onTap: () => Navigator.pop(context, option.value),
              ),
              if (option != options.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _DocumentTypeTile extends StatelessWidget {
  const _DocumentTypeTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : const Color(0xFFFFFAF7),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.32)
                : AppColors.primary.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : AppColors.textGrey,
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool hasImage;
  final VoidCallback? onTap;

  const _UploadRow({
    required this.title,
    required this.subtitle,
    required this.hasImage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Icon(
              hasImage ? Icons.check_rounded : Icons.image_outlined,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SecondaryButton(
            label: hasImage ? 'Change' : 'Upload',
            onPressed: onTap,
            expand: false,
            size: AppButtonSize.compact,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            SecondaryButton(
              label: 'Try Again',
              onPressed: () => onRetry(),
              expand: false,
            ),
          ],
        ),
      ),
    );
  }
}
