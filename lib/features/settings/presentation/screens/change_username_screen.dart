import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/identity/username_utils.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../widgets/custom_button.dart';
import '../../../auth/data/services/auth_service.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../domain/models/username_change_models.dart';
import '../../../auth/presentation/widgets/auth_input_field.dart';
import '../../../auth/presentation/widgets/auth_shell.dart';

class ChangeUsernameScreen extends StatefulWidget {
  final String currentUsername;

  const ChangeUsernameScreen({super.key, required this.currentUsername});

  @override
  State<ChangeUsernameScreen> createState() => _ChangeUsernameScreenState();
}

class _ChangeUsernameScreenState extends State<ChangeUsernameScreen> {
  static const _debounceDuration = Duration(milliseconds: 450);

  final AuthService _authService = AuthService();
  final ProfileRepository _profileRepository = ProfileRepository();
  final TextEditingController _usernameController = TextEditingController();

  Timer? _debounce;
  String? _usernameError;
  bool _isSubmitting = false;
  UsernameAvailabilityState _availabilityState =
      UsernameAvailabilityState.unchanged;

  String get _currentNormalizedUsername =>
      normalizeUsername(widget.currentUsername);

  @override
  void initState() {
    super.initState();
    _usernameController.text = _currentNormalizedUsername;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  void _handleUsernameChanged(String value) {
    final normalized = normalizeUsername(value);
    if (normalized != value) {
      _usernameController.value = TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(offset: normalized.length),
      );
    }

    final validationError = validateNormalizedUsername(normalized);
    setState(() {
      _usernameError = validationError;
      _availabilityState = normalized == _currentNormalizedUsername
          ? UsernameAvailabilityState.unchanged
          : validationError != null
          ? UsernameAvailabilityState.invalid
          : UsernameAvailabilityState.checking;
    });

    _debounce?.cancel();
    if (normalized == _currentNormalizedUsername || validationError != null) {
      return;
    }

    _debounce = Timer(_debounceDuration, () async {
      final currentUserId = _authService.currentUser?.uid.trim() ?? '';
      try {
        final isAvailable = await _profileRepository.isUsernameAvailable(
          normalized,
          excludeUid: currentUserId,
        );
        if (!mounted || _usernameController.text.trim() != normalized) return;
        setState(() {
          _availabilityState = isAvailable
              ? UsernameAvailabilityState.available
              : UsernameAvailabilityState.unavailable;
        });
      } catch (_) {
        if (!mounted || _usernameController.text.trim() != normalized) return;
        setState(() {
          _availabilityState = UsernameAvailabilityState.unavailable;
        });
      }
    });
  }

  Future<void> _submit() async {
    final normalized = normalizeUsername(_usernameController.text);
    final validationError = validateNormalizedUsername(normalized);

    setState(() {
      _usernameError = validationError;
    });
    if (validationError != null) {
      setState(() => _availabilityState = UsernameAvailabilityState.invalid);
      return;
    }
    if (normalized == _currentNormalizedUsername) {
      setState(() => _availabilityState = UsernameAvailabilityState.unchanged);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _authService.changeUsername(username: normalized);
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Your username has been updated.',
        tone: AppFeedbackTone.success,
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthShell(
      title: 'Change Username',
      subtitle:
          'Your UID stays the same. Pettxo will reserve the new username atomically before updating your profile.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AuthInputField(
            controller: _usernameController,
            labelText: 'Username',
            prefixText: '@',
            errorText: _usernameError,
            helperText: '3-20 lowercase letters, numbers, dots, or underscores',
            maxLength: 20,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
            ],
            onChanged: _handleUsernameChanged,
          ),
          const SizedBox(height: 10),
          Text(
            _availabilityLabel(),
            style: TextStyle(
              color: _availabilityColor(),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          CustomButton(
            text: _isSubmitting ? 'Updating...' : 'Change Username',
            onPressed: _isSubmitting ? null : _submit,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  String _availabilityLabel() {
    return switch (_availabilityState) {
      UsernameAvailabilityState.unchanged => 'Unchanged',
      UsernameAvailabilityState.checking => 'Checking',
      UsernameAvailabilityState.available => 'Available',
      UsernameAvailabilityState.unavailable => 'Unavailable',
      UsernameAvailabilityState.invalid => 'Invalid',
    };
  }

  Color _availabilityColor() {
    return switch (_availabilityState) {
      UsernameAvailabilityState.available => const Color(0xFF1F8A4C),
      UsernameAvailabilityState.invalid ||
      UsernameAvailabilityState.unavailable => const Color(0xFFE15656),
      UsernameAvailabilityState.checking => const Color(0xFFB86A07),
      UsernameAvailabilityState.unchanged => const Color(0xFF8E8479),
    };
  }
}
