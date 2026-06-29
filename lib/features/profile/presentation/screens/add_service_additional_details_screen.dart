import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/app_loader.dart';
import '../../../../core/services/policy_link_service.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/legal_consent_checkbox.dart';
import '../../../auth/data/services/user_service.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';
import '../../../provider/data/repositories/provider_onboarding_repository.dart';
import '../../../provider/domain/models/provider_onboarding_models.dart';
import '../../../provider/presentation/screens/provider_bank_details_screen.dart';
import '../../../provider/presentation/screens/provider_verification_screen.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/models/add_service_flow_draft.dart';
import '../../domain/models/user_profile.dart';
import '../../../services/data/repositories/services_repository.dart';
import '../../../services/domain/models/service_model.dart';

class AddServiceAdditionalDetailsScreen extends StatefulWidget {
  final AddServiceFlowDraft draft;

  const AddServiceAdditionalDetailsScreen({super.key, required this.draft});

  @override
  State<AddServiceAdditionalDetailsScreen> createState() =>
      _AddServiceAdditionalDetailsScreenState();
}

class _AddServiceAdditionalDetailsScreenState
    extends State<AddServiceAdditionalDetailsScreen> {
  static const Color _screenBackground = Color(0xFFFCF8F5);
  static const int _maxPhotos = 6;
  static const int _maxPhotoSizeBytes = 5 * 1024 * 1024;
  static const List<String> _allowedExtensions = ['jpg', 'jpeg', 'png', 'webp'];

  final ImagePicker _imagePicker = ImagePicker();
  final TextEditingController _notesController = TextEditingController();
  final FocusNode _notesFocusNode = FocusNode();
  final GlobalKey _notesFieldKey = GlobalKey();
  final ProfileRepository _profileRepository = ProfileRepository();
  final ServicesRepository _servicesRepository = ServicesRepository();
  final ProviderOnboardingRepository _providerOnboardingRepository =
      ProviderOnboardingRepository();
  final UserService _userService = UserService();

  final List<_SelectedPhoto> _selectedPhotos = [];
  String? _notesError;
  bool _isPublishing = false;
  bool _highlightNotes = false;
  bool _acceptedProviderAgreement = false;
  bool _hasStoredProviderAgreement = false;
  String? _providerConsentError;

  bool get _isFormValid => _notesController.text.trim().length <= 300;

  bool get _hasValidFlowDraft {
    final details = widget.draft.details;
    final setup = widget.draft.bookingSetup;

    return details.resolvedAnimalType.isNotEmpty &&
        details.resolvedCategory.isNotEmpty &&
        details.serviceName.trim().isNotEmpty &&
        details.pricePerSession > 0 &&
        details.description.trim().isNotEmpty &&
        setup.sessionDurationMinutes > 0 &&
        setup.capacity > 0 &&
        setup.availableDays.isNotEmpty &&
        setup.endMinutes > setup.startMinutes &&
        setup.location.displayAddress.trim().isNotEmpty &&
        setup.location.hasValidCoordinates &&
        setup.serviceType.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _loadProviderAgreementStatus();
  }

  Future<void> _loadProviderAgreementStatus() async {
    try {
      final hasAccepted = await _userService.hasAcceptedProviderAgreement();
      if (!mounted) return;
      setState(() {
        _hasStoredProviderAgreement = hasAccepted;
      });
    } catch (_) {
      // Best-effort preload only.
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _notesFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final remaining = _maxPhotos - _selectedPhotos.length;
    if (remaining <= 0) {
      AppFeedback.show(
        context,
        message: 'You can add up to 6 photos only.',
        tone: AppFeedbackTone.info,
      );
      return;
    }

    final files = await _imagePicker.pickMultiImage();
    if (!mounted || files.isEmpty) return;

    final accepted = <_SelectedPhoto>[];

    // Validation stays frontend-only for now: the files are kept in memory
    // and their local paths are reused to preview the mock published service.
    for (final file in files) {
      final extension = file.path.split('.').last.toLowerCase();
      if (!_allowedExtensions.contains(extension)) {
        if (!mounted) return;
        AppFeedback.show(
          context,
          message: 'Unsupported image format. Use JPG, JPEG, PNG, or WEBP.',
          tone: AppFeedbackTone.error,
        );
        continue;
      }

      final imageFile = File(file.path);
      final fileSize = await imageFile.length();
      if (fileSize > _maxPhotoSizeBytes) {
        if (!mounted) return;
        AppFeedback.show(
          context,
          message: 'Each photo must be 5 MB or smaller.',
          tone: AppFeedbackTone.error,
        );
        continue;
      }

      accepted.add(_SelectedPhoto(path: file.path, name: file.name));
    }

    if (!mounted || accepted.isEmpty) return;

    setState(() {
      _selectedPhotos.addAll(accepted.take(remaining));
    });

    if (accepted.length > remaining) {
      AppFeedback.show(
        context,
        message: 'Only the first $remaining photos were added.',
        tone: AppFeedbackTone.info,
      );
    }
  }

  bool _validateForm() {
    setState(() {
      _notesError = _notesController.text.trim().length > 300
          ? 'Notes must be 300 characters or less'
          : null;
    });

    return _isFormValid && _hasValidFlowDraft;
  }

  Future<void> _showPublishGuidance() async {
    if (_notesController.text.trim().length > 300) {
      setState(() {
        _highlightNotes = true;
      });
      AppFeedback.show(
        context,
        message: 'Notes must be 300 characters or less before publishing.',
        tone: AppFeedbackTone.info,
      );

      final fieldContext = _notesFieldKey.currentContext;
      if (fieldContext != null) {
        await Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.18,
        );
      }
      _notesFocusNode.requestFocus();
      return;
    }

    AppFeedback.show(
      context,
      message: 'Complete the previous steps before publishing this service.',
      tone: AppFeedbackTone.info,
    );
  }

  Future<void> _handlePublishPress() async {
    if (!UserRestrictionService.instance.ensureCanUseBookingFeatures(context)) {
      return;
    }
    if (_validateForm()) {
      await _publishService();
      return;
    }

    await _showPublishGuidance();
  }

  Future<void> _publishService() async {
    if (!_validateForm() || _isPublishing) return;
    if (!_hasStoredProviderAgreement && !_acceptedProviderAgreement) {
      setState(() {
        _providerConsentError =
            'You must agree to the Service Provider Agreement.';
      });
      AppFeedback.show(
        context,
        message: 'Please review and accept the Service Provider Agreement.',
        tone: AppFeedbackTone.info,
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      if (!_hasStoredProviderAgreement) {
        await _userService.acceptProviderAgreementIfNeeded();
      }
      final onboardingReady = await _ensureProviderOnboardingReady();
      if (!onboardingReady) return;

      final onboarding = await _providerOnboardingRepository
          .fetchCurrentOnboarding();
      final firstServiceDraftGraceEndsAt =
          onboarding.verification.firstServiceListedAt == null &&
              !onboarding.hasListedService
          ? DateTime.now().add(const Duration(hours: 72))
          : onboarding.verification.gracePeriodEndsAt;

      AppLoader.showWithMessage(
        _selectedPhotos.isEmpty
            ? 'Setting up your service...'
            : 'Uploading images...',
      );

      final profile = await _profileRepository.getCurrentUserProfile();
      final service = _buildServiceModel(
        profile,
        verification: onboarding.verification,
        gracePeriodEndsAt: firstServiceDraftGraceEndsAt,
      );
      final photos = _selectedPhotos.map((photo) => File(photo.path)).toList();

      // Publish now writes to Firestore and uploads selected photos to Storage.
      // Moderation fields are included so admin review can be added without
      // reshaping service documents later.
      await _servicesRepository.createService(service: service, photos: photos);
      if (firstServiceDraftGraceEndsAt != null) {
        await _providerOnboardingRepository.markFirstServiceListedIfNeeded(
          gracePeriodEndsAt: firstServiceDraftGraceEndsAt,
        );
      }
      await _providerOnboardingRepository
          .syncServicesForCurrentVerificationStatus();

      AppLoader.hide();
      if (!mounted) return;

      AppFeedback.show(
        context,
        message: 'Service published and added to your profile.',
        tone: AppFeedbackTone.success,
      );
      Navigator.pop(context, true);
    } catch (_) {
      AppLoader.hide();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not publish this service right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      AppLoader.hide();
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }

  Future<bool> _ensureProviderOnboardingReady() async {
    await _providerOnboardingRepository
        .syncServicesForCurrentVerificationStatus();
    var onboarding = await _providerOnboardingRepository
        .fetchCurrentOnboarding();

    if (!onboarding.verification.isSubmitted ||
        onboarding.verification.isRejected) {
      if (!mounted) return false;
      final submitted = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const ProviderVerificationScreen()),
      );
      if (!mounted || submitted != true) {
        return false;
      }
      onboarding = await _providerOnboardingRepository.fetchCurrentOnboarding();
      if (!mounted) return false;
    }

    if (!onboarding.bankDetails.isSubmitted) {
      if (!mounted) return false;
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const ProviderBankDetailsScreen()),
      );
      if (!mounted || saved != true) {
        return false;
      }
      onboarding = await _providerOnboardingRepository.fetchCurrentOnboarding();
      if (!mounted) return false;
    }

    await _providerOnboardingRepository
        .syncServicesForCurrentVerificationStatus();
    onboarding = await _providerOnboardingRepository.fetchCurrentOnboarding();
    if (!mounted) return false;

    if (onboarding.verification.graceExpired &&
        !onboarding.verification.isApproved) {
      AppFeedback.show(
        context,
        message:
            'Your services are paused until provider verification is approved.',
        tone: AppFeedbackTone.info,
      );
      return false;
    }

    if (!onboarding.verification.isApproved &&
        onboarding.verification.isPending) {
      AppFeedback.show(
        context,
        message: onboarding.hasListedService
            ? 'Your services are active while verification is under review.'
            : 'Your verification is under review. Your first service will stay active during the 72-hour grace period.',
        tone: AppFeedbackTone.info,
      );
    }

    return true;
  }

  ServiceModel _buildServiceModel(
    UserProfile profile, {
    required ProviderVerificationRecord verification,
    required DateTime? gracePeriodEndsAt,
  }) {
    final details = widget.draft.details;
    final setup = widget.draft.bookingSetup;

    return ServiceModel(
      id: '',
      ownerUserId: profile.uid,
      ownerName: profile.name,
      ownerUsername: profile.username,
      ownerPhotoUrl: profile.profileImageUrl,
      ownerCity: profile.city,
      ownerState: profile.state,
      title: details.serviceName,
      animalType: details.resolvedAnimalType,
      category: details.resolvedCategory,
      description: details.description,
      privateNotes: _notesController.text.trim(),
      pricePerSession: details.pricePerSession,
      currency: 'INR',
      sessionDurationMinutes: setup.sessionDurationMinutes,
      capacity: setup.capacity,
      availableDays: setup.availableDays,
      startMinutes: setup.startMinutes,
      endMinutes: setup.endMinutes,
      sameForAllDays: setup.sameForAllDays,
      serviceType: setup.serviceType,
      displayAddress: setup.location.displayAddress,
      latitude: setup.location.latitude,
      longitude: setup.location.longitude,
      city: profile.city,
      state: profile.state,
      photoUrls: const [],
      primaryPhotoUrl: '',
      status: 'active',
      isActive: true,
      isDeleted: false,
      isPaused: false,
      moderationStatus: 'pending',
      isVisibleToMarketplace: true,
      providerVerificationStatus: verification.status,
      providerVerificationGraceEndsAt: gracePeriodEndsAt,
      isPausedByVerification: false,
      pauseReason: '',
      ratingAverage: 0,
      ratingCount: 0,
      createdAt: null,
      updatedAt: null,
      publishedAt: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topContentPadding = topInset + 108;

    return Scaffold(
      backgroundColor: _screenBackground,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            ListView(
              padding: EdgeInsets.fromLTRB(
                18,
                topContentPadding,
                18,
                bottomInset + 28,
              ),
              children: [
                const _IntroCard(
                  title: 'Additional Details',
                  subtitle:
                      'Add optional photos and private notes to make your service feel complete before publishing.',
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Add photos',
                  children: [
                    const Text(
                      'Show your space, past work, or setup. This builds trust.',
                      style: TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_selectedPhotos.length} / $_maxPhotos selected',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        ..._selectedPhotos.asMap().entries.map((entry) {
                          return _PhotoTile(
                            photo: entry.value,
                            onRemove: () {
                              setState(() {
                                _selectedPhotos.removeAt(entry.key);
                              });
                            },
                          );
                        }),
                        if (_selectedPhotos.length < _maxPhotos)
                          _AddPhotoTile(onTap: _pickPhotos),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Supports JPG, JPEG, PNG, and WEBP up to 5 MB each. Service cards will later crop these previews to square (1:1).',
                      style: TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Instructions or notes (optional)',
                  children: [
                    _NotesField(
                      fieldKey: _notesFieldKey,
                      controller: _notesController,
                      focusNode: _notesFocusNode,
                      errorText: _notesError,
                      isHighlighted: _highlightNotes,
                      onChanged: (_) {
                        setState(() {
                          _notesError = null;
                          _highlightNotes = false;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionCard(
                  title: 'Ready to publish',
                  children: const [_WarningNotice()],
                ),
                if (!_hasStoredProviderAgreement) ...[
                  const SizedBox(height: 18),
                  _SectionCard(
                    title: 'Provider Agreement',
                    children: [
                      LegalConsentCheckbox(
                        value: _acceptedProviderAgreement,
                        onChanged: (value) {
                          setState(() {
                            _acceptedProviderAgreement = value ?? false;
                            if (_acceptedProviderAgreement) {
                              _providerConsentError = null;
                            }
                          });
                        },
                        errorText: _providerConsentError,
                        segments: [
                          const LegalConsentSegment(text: 'I agree to the '),
                          LegalConsentSegment(
                            text: 'Service Provider Agreement',
                            onTap: () => PolicyLinkService
                                .openExternalPolicyUrlWithFeedback(
                                  context,
                                  PolicyLinkService.providerPolicyKey,
                                ),
                          ),
                          const LegalConsentSegment(text: '.'),
                        ],
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                Stack(
                  children: [
                    GradientButton(
                      label: _isPublishing
                          ? 'Publishing...'
                          : 'Publish Service',
                      onPressed:
                          _isFormValid && _hasValidFlowDraft && !_isPublishing
                          ? _handlePublishPress
                          : null,
                    ),
                    if ((!_isFormValid || !_hasValidFlowDraft) &&
                        !_isPublishing)
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _handlePublishPress,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              top: topInset + 10,
              child: Align(
                child: FractionallySizedBox(
                  widthFactor: 0.85,
                  child: GlassSurface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    backgroundColor: Colors.white.withValues(alpha: 0.72),
                    blurSigma: 20,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        blurRadius: 22,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.56),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Additional Details',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
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

class _SelectedPhoto {
  final String path;
  final String name;

  const _SelectedPhoto({required this.path, required this.name});
}

class _IntroCard extends StatelessWidget {
  final String title;
  final String subtitle;

  const _IntroCard({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _AddPhotoTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddPhotoTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 102,
        height: 102,
        decoration: BoxDecoration(
          color: const Color(0xFFFCFBFA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.16),
            style: BorderStyle.solid,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_outlined, color: AppColors.primary),
            SizedBox(height: 8),
            Text(
              'Add photo',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final _SelectedPhoto photo;
  final VoidCallback onRemove;

  const _PhotoTile({required this.photo, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 102,
      height: 102,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.file(
                File(photo.path),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCFBFA),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textGrey,
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.44),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                photo.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotesField extends StatelessWidget {
  final Key? fieldKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? errorText;
  final bool isHighlighted;
  final ValueChanged<String> onChanged;

  const _NotesField({
    this.fieldKey,
    required this.controller,
    this.focusNode,
    required this.errorText,
    this.isHighlighted = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final currentLength = controller.text.length;

    return Column(
      key: fieldKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: 5,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText:
                'e.g. Please bring vaccination records. Pickup only after 6 PM.',
            helperText:
                'Shown to the pet parent only after booking is confirmed.',
            errorText: errorText,
            filled: true,
            fillColor: const Color(0xFFFCFBFA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: isHighlighted
                  ? const BorderSide(color: AppColors.primary, width: 1.6)
                  : BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: isHighlighted
                  ? const BorderSide(color: AppColors.primary, width: 1.6)
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.6,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '$currentLength / 300',
            style: TextStyle(
              color: currentLength > 300
                  ? Colors.redAccent
                  : AppColors.textGrey,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _WarningNotice extends StatelessWidget {
  const _WarningNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.primary),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Once published, this service can be booked by pet parents in your area. Cancellations and no-shows follow platform rules and cannot be manually overridden.',
              style: TextStyle(
                color: AppColors.textDark,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
