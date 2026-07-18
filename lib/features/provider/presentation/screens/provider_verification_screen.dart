import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/policy_link_service.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/legal_consent_checkbox.dart';
import '../../../auth/data/services/user_service.dart';
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
  final UserService _userService = UserService();

  ProviderVerificationRecord? _verification;
  String _selectedDocumentType = 'aadhaar';
  _SelectedVerificationDocument? _frontDocument;
  _SelectedVerificationDocument? _backDocument;
  bool _acceptedProviderAgreement = false;
  bool _hasStoredProviderAgreement = false;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _loadError;
  String? _consentError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repository.fetchCurrentVerification(),
        _userService.hasAcceptedProviderAgreement(),
      ]);
      final verification = results[0] as ProviderVerificationRecord;
      final hasAcceptedProviderAgreement = results[1] as bool;
      if (!mounted) return;
      setState(() {
        _verification = verification;
        _hasStoredProviderAgreement = hasAcceptedProviderAgreement;
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
        _frontDocument = _SelectedVerificationDocument.image(File(file.path));
      } else {
        _backDocument = _SelectedVerificationDocument.image(File(file.path));
      }
    });
  }

  Future<void> _pickPdf({required bool isFront}) async {
    const pdfTypeGroup = XTypeGroup(
      label: 'PDF documents',
      extensions: <String>['pdf'],
    );
    final picked = await openFile(acceptedTypeGroups: const [pdfTypeGroup]);
    if (!mounted || picked == null) return;
    final path = picked.path;
    if (path.trim().isEmpty) return;
    final document = _SelectedVerificationDocument.pdf(
      File(path),
      picked.name.trim().isEmpty ? 'document.pdf' : picked.name.trim(),
    );
    setState(() {
      if (isFront) {
        _frontDocument = document;
      } else {
        _backDocument = document;
      }
    });
  }

  Future<void> _pickDocument({required bool isFront}) async {
    final selectedType = await showModalBottomSheet<_VerificationPickerType>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const _DocumentSourceSheet(),
    );
    if (!mounted || selectedType == null) return;
    if (selectedType == _VerificationPickerType.image) {
      await _pickImage(isFront: isFront);
      return;
    }
    await _pickPdf(isFront: isFront);
  }

  Future<void> _openSubmittedDocument({
    required String url,
    required bool isPdf,
    required String title,
  }) async {
    if (url.trim().isEmpty) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'This document link is unavailable right now.',
        tone: AppFeedbackTone.error,
      );
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dialogContext) => _SubmittedDocumentPreviewDialog(
        title: title,
        documentUrl: url.trim(),
        isPdf: isPdf,
      ),
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (_frontDocument == null) {
      AppFeedback.show(
        context,
        message: 'Upload the front side of your identity proof first.',
        tone: AppFeedbackTone.info,
      );
      return;
    }
    if (!_hasStoredProviderAgreement && !_acceptedProviderAgreement) {
      setState(() {
        _consentError = 'You must agree to the Service Provider Agreement.';
      });
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      if (!_hasStoredProviderAgreement) {
        await _userService.acceptProviderAgreementIfNeeded();
      }
      await _repository.submitVerification(
        documentType: _selectedDocumentType,
        frontDocument: _frontDocument!.toUploadFile(),
        backDocument: _backDocument?.toUploadFile(),
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
                  frontDocument: _frontDocument,
                  backDocument: _backDocument,
                  onPickFront: () => _pickDocument(isFront: true),
                  onPickBack: () => _pickDocument(isFront: false),
                  verification: verification,
                  onViewFront: verification.hasFrontDocument
                      ? () => _openSubmittedDocument(
                          url: verification.documentFrontUrl,
                          isPdf: verification.frontDocumentIsPdf,
                          title: 'Front document',
                        )
                      : null,
                  onViewBack: verification.hasBackDocument
                      ? () => _openSubmittedDocument(
                          url: verification.documentBackUrl,
                          isPdf: verification.backDocumentIsPdf,
                          title: 'Back document',
                        )
                      : null,
                ),
                if (!_hasStoredProviderAgreement) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                    ),
                    child: LegalConsentCheckbox(
                      value: _acceptedProviderAgreement,
                      onChanged: (value) {
                        setState(() {
                          _acceptedProviderAgreement = value ?? false;
                          if (_acceptedProviderAgreement) {
                            _consentError = null;
                          }
                        });
                      },
                      errorText: _consentError,
                      segments: [
                        const LegalConsentSegment(text: 'I agree to the '),
                        LegalConsentSegment(
                          text: 'Service Provider Agreement',
                          onTap: () =>
                              PolicyLinkService.openExternalPolicyUrlWithFeedback(
                                context,
                                PolicyLinkService.providerPolicyKey,
                              ),
                        ),
                        const LegalConsentSegment(text: '.'),
                      ],
                    ),
                  ),
                ],
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
  final _SelectedVerificationDocument? frontDocument;
  final _SelectedVerificationDocument? backDocument;
  final VoidCallback onPickFront;
  final VoidCallback onPickBack;
  final VoidCallback? onViewFront;
  final VoidCallback? onViewBack;
  final ProviderVerificationRecord verification;

  const _FormCard({
    required this.enabled,
    required this.selectedDocumentType,
    required this.onDocumentTypeChanged,
    required this.frontDocument,
    required this.backDocument,
    required this.onPickFront,
    required this.onPickBack,
    required this.onViewFront,
    required this.onViewBack,
    required this.verification,
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
            title: 'Front document',
            subtitle: frontDocument != null
                ? frontDocument!.summaryLabel
                : verification.hasFrontDocument
                ? verification.frontDocumentIsPdf
                      ? 'A PDF document is already on file.'
                      : 'A document image is already on file.'
                : 'Upload a clear image or PDF of the front side.',
            hasDocument: frontDocument != null || verification.hasFrontDocument,
            onTap: enabled ? onPickFront : null,
            onView: onViewFront,
            isPdf:
                frontDocument?.isPdf == true || verification.frontDocumentIsPdf,
          ),
          const SizedBox(height: 12),
          _UploadRow(
            title: 'Back document (optional)',
            subtitle: backDocument != null
                ? backDocument!.summaryLabel
                : verification.hasBackDocument
                ? verification.backDocumentIsPdf
                      ? 'A back-side PDF is already on file.'
                      : 'A back-side image is already on file.'
                : 'Add the back side as an image or PDF if it includes important details.',
            hasDocument: backDocument != null || verification.hasBackDocument,
            onTap: enabled ? onPickBack : null,
            onView: onViewBack,
            isPdf:
                backDocument?.isPdf == true || verification.backDocumentIsPdf,
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
              FocusManager.instance.primaryFocus?.unfocus();
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
  final bool hasDocument;
  final bool isPdf;
  final VoidCallback? onTap;
  final VoidCallback? onView;

  const _UploadRow({
    required this.title,
    required this.subtitle,
    required this.hasDocument,
    required this.isPdf,
    required this.onTap,
    this.onView,
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
              hasDocument
                  ? (isPdf ? Icons.picture_as_pdf_rounded : Icons.check_rounded)
                  : Icons.upload_file_outlined,
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
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SecondaryButton(
                label: hasDocument ? 'Change' : 'Upload',
                onPressed: onTap,
                expand: false,
                size: AppButtonSize.compact,
              ),
              if (hasDocument && onView != null) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: onView, child: const Text('View')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

enum _VerificationPickerType { image, pdf }

class _DocumentSourceSheet extends StatelessWidget {
  const _DocumentSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
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
              'Choose upload type',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload a clear image from your gallery or select a PDF document.',
              style: TextStyle(color: AppColors.textGrey, height: 1.45),
            ),
            const SizedBox(height: 16),
            _DocumentTypeTile(
              icon: Icons.image_outlined,
              label: 'Upload image',
              selected: false,
              onTap: () =>
                  Navigator.pop(context, _VerificationPickerType.image),
            ),
            const SizedBox(height: 10),
            _DocumentTypeTile(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Upload PDF',
              selected: false,
              onTap: () => Navigator.pop(context, _VerificationPickerType.pdf),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedVerificationDocument {
  const _SelectedVerificationDocument({
    required this.file,
    required this.fileName,
    required this.contentType,
  });

  factory _SelectedVerificationDocument.image(File file) {
    return _SelectedVerificationDocument(
      file: file,
      fileName: file.path.split(Platform.pathSeparator).last,
      contentType: 'image/jpeg',
    );
  }

  factory _SelectedVerificationDocument.pdf(File file, String fileName) {
    return _SelectedVerificationDocument(
      file: file,
      fileName: fileName,
      contentType: 'application/pdf',
    );
  }

  final File file;
  final String fileName;
  final String contentType;

  bool get isPdf => contentType == 'application/pdf';

  String get summaryLabel =>
      isPdf ? 'Selected PDF: $fileName' : 'Selected image: $fileName';

  ProviderVerificationUploadFile toUploadFile() {
    return ProviderVerificationUploadFile(
      file: file,
      fileName: fileName,
      contentType: contentType,
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

class _SubmittedDocumentPreviewDialog extends StatelessWidget {
  const _SubmittedDocumentPreviewDialog({
    required this.title,
    required this.documentUrl,
    required this.isPdf,
  });

  final String title;
  final String documentUrl;
  final bool isPdf;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(size.width - 24, 520.0);
    final dialogHeight = math.min(size.height * 0.8, 720.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.08,
                      ),
                      minimumSize: const Size(40, 40),
                    ),
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
                child: ColoredBox(
                  color: const Color(0xFFF9F4EF),
                  child: isPdf
                      ? _PdfDocumentPreview(documentUrl: documentUrl)
                      : InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: Center(
                            child: Image.network(
                              documentUrl,
                              fit: BoxFit.contain,
                              loadingBuilder:
                                  (context, child, loadingProgress) =>
                                      loadingProgress == null
                                      ? child
                                      : const Center(
                                          child: CircularProgressIndicator(),
                                        ),
                              errorBuilder: (context, error, stackTrace) =>
                                  const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'We could not load this document preview right now.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: AppColors.textGrey,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                            ),
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

class _PdfDocumentPreview extends StatefulWidget {
  const _PdfDocumentPreview({required this.documentUrl});

  final String documentUrl;

  @override
  State<_PdfDocumentPreview> createState() => _PdfDocumentPreviewState();
}

class _PdfDocumentPreviewState extends State<_PdfDocumentPreview> {
  PdfControllerPinch? _controller;
  Object? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final bytes = await _downloadPdfBytes(widget.documentUrl);
      final controller = PdfControllerPinch(
        document: PdfDocument.openData(bytes),
      );
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _isLoading = false;
      });
    }
  }

  Future<Uint8List> _downloadPdfBytes(String url) async {
    final uri = Uri.parse(url);
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load PDF');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null || _controller == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'We could not load this PDF preview right now.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    return PdfViewPinch(
      controller: _controller!,
      backgroundDecoration: const BoxDecoration(color: Color(0xFFF9F4EF)),
    );
  }
}
