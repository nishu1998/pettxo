import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../auth/presentation/widgets/common_phone_field.dart';
import '../../data/support_repository.dart';
import '../../data/support_phone_utils.dart';
import '../../domain/models/support_models.dart';
import 'support_ticket_detail_screen.dart';

class CreateSupportTicketScreen extends StatefulWidget {
  const CreateSupportTicketScreen({super.key});

  @override
  State<CreateSupportTicketScreen> createState() =>
      _CreateSupportTicketScreenState();
}

class _CreateSupportTicketScreenState extends State<CreateSupportTicketScreen> {
  static const int _maxAttachments = 3;
  static const int _maxAttachmentSizeBytes = 5 * 1024 * 1024;
  static const List<String> _allowedExtensions = <String>[
    'jpg',
    'jpeg',
    'png',
    'webp',
  ];

  final SupportRepository _repository = SupportRepository();
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final List<_DraftAttachment> _attachments = <_DraftAttachment>[];

  SupportTicketCategory _category = SupportTicketCategory.booking;
  String _contactNumber =
      FirebaseAuth.instance.currentUser?.phoneNumber?.trim() ?? '';
  String? _contactNumberError;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    final contactNumberError = validateSupportContactNumber(_contactNumber);
    setState(() => _contactNumberError = contactNumberError);
    if (form == null ||
        !form.validate() ||
        contactNumberError != null ||
        _isSubmitting) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    String? ticketId;
    var uploadedAttachments = const <SupportUploadedTicketAttachment>[];
    try {
      ticketId = await _repository.createSupportTicket(
        category: _category,
        subject: _subjectController.text.trim(),
        description: _descriptionController.text.trim(),
        contactNumber: normalizeSupportContactNumber(_contactNumber),
      );
      if (_attachments.isNotEmpty) {
        uploadedAttachments = await _repository.uploadDraftAttachments(
          ticketId: ticketId,
          attachments: _attachments
              .map(
                (attachment) => SupportTicketDraftAttachment(
                  bytes: attachment.bytes,
                  fileName: attachment.fileName,
                  contentType: attachment.contentType,
                ),
              )
              .toList(growable: false),
        );
        await _repository.finalizeSupportTicketAttachments(
          ticketId: ticketId,
          attachments: uploadedAttachments,
        );
      }
      final createdTicketId = ticketId;
      if (!mounted || createdTicketId.isEmpty) {
        return;
      }
      AppSnackbar.showSuccess(context, 'Your support ticket has been created.');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SupportTicketDetailScreen(ticketId: createdTicketId),
        ),
      );
    } catch (error) {
      if (uploadedAttachments.isNotEmpty) {
        await _repository.cleanupUploadedAttachments(uploadedAttachments);
      }
      if (!mounted) return;
      if (ticketId != null && ticketId.isNotEmpty) {
        AppSnackbar.showWarning(
          context,
          'Your ticket was created, but the attachments could not be saved.',
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SupportTicketDetailScreen(ticketId: ticketId!),
          ),
        );
        return;
      }
      AppSnackbar.showError(context, _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _pickAttachments() async {
    final remaining = _maxAttachments - _attachments.length;
    if (remaining <= 0) {
      AppSnackbar.showInfo(
        context,
        'You can attach up to 3 screenshots or photos.',
      );
      return;
    }

    final files = await _imagePicker.pickMultiImage();
    if (!mounted || files.isEmpty) return;

    final accepted = <_DraftAttachment>[];
    for (final file in files) {
      if (accepted.length >= remaining) break;
      final extension = file.name.split('.').last.toLowerCase();
      if (!_allowedExtensions.contains(extension)) {
        if (!mounted) return;
        AppSnackbar.showError(
          context,
          'Only JPG, JPEG, PNG, or WEBP images are supported.',
        );
        continue;
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (!mounted) return;
        AppSnackbar.showError(context, 'One selected image is empty.');
        continue;
      }
      if (bytes.length > _maxAttachmentSizeBytes) {
        if (!mounted) return;
        AppSnackbar.showError(
          context,
          'Each attachment must be 5 MB or smaller.',
        );
        continue;
      }

      accepted.add(
        _DraftAttachment(
          fileName: file.name,
          contentType: _contentTypeForExtension(extension),
          bytes: bytes,
        ),
      );
    }

    if (!mounted || accepted.isEmpty) return;
    setState(() {
      _attachments.addAll(accepted.take(remaining));
    });
  }

  void _removeAttachment(_DraftAttachment attachment) {
    setState(() => _attachments.remove(attachment));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        title: const Text(
          'Raise a Support Ticket',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.97),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Category',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<SupportTicketCategory>(
                      initialValue: _category,
                      items: SupportTicketCategory.values
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(category.label),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _category = value);
                      },
                      decoration: _inputDecoration('Select a category'),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Subject',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _subjectController,
                      maxLength: 120,
                      textInputAction: TextInputAction.next,
                      decoration: _inputDecoration(
                        'Briefly summarize the issue',
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'Enter a subject.';
                        if (text.length < 4) {
                          return 'Subject is too short.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Description',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 6,
                      maxLines: 10,
                      maxLength: 4000,
                      decoration: _inputDecoration(
                        'Tell us what happened and include any useful details.',
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty) return 'Enter a description.';
                        if (text.length < 10) {
                          return 'Please share a little more detail.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Contact Number',
                      style: TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    CommonPhoneField(
                      initialNumber: supportPhoneFieldInitialNumber(
                        _contactNumber,
                      ),
                      errorText: _contactNumberError,
                      labelText: 'Contact number',
                      enabled: !_isSubmitting,
                      onChanged: (value) {
                        final normalized = normalizeSupportContactNumber(value);
                        if (_contactNumber == normalized &&
                            _contactNumberError == null) {
                          return;
                        }
                        setState(() {
                          _contactNumber = normalized;
                          _contactNumberError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'We may use this number to contact you if your issue cannot be resolved through the support ticket.',
                      style: TextStyle(
                        color: AppColors.textGrey,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Optional screenshots / photos',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _isSubmitting ? null : _pickAttachments,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(
                            _attachments.isEmpty ? 'Add images' : 'Add more',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Attach up to 3 images. Screenshots and photos only, maximum 5 MB each.',
                      style: TextStyle(
                        color: AppColors.textGrey,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_attachments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 96,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _attachments.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            final attachment = _attachments[index];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Image.memory(
                                    attachment.bytes,
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Material(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _isSubmitting
                                          ? null
                                          : () => _removeAttachment(attachment),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(
                                          Icons.close_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primary.withValues(
                    alpha: 0.45,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit ticket',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: AppColors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('unauthenticated')) {
      return 'Please sign in again and try once more.';
    }
    if (message.contains('failed-precondition')) {
      return 'Your account is not ready to create a support ticket right now.';
    }
    return 'We could not create your support ticket right now.';
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }
}

class _DraftAttachment {
  const _DraftAttachment({
    required this.fileName,
    required this.contentType,
    required this.bytes,
  });

  final String fileName;
  final String contentType;
  final Uint8List bytes;
}
