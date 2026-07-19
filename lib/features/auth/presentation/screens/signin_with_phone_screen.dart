import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/services/auth_service.dart';
import '../../domain/models/phone_auth_flow.dart';
import 'auth_gateway_screen.dart';
import 'otp_verification_screen.dart';

class SignInWithPhoneScreen extends StatefulWidget {
  const SignInWithPhoneScreen({super.key});

  @override
  State<SignInWithPhoneScreen> createState() => _SignInWithPhoneScreenState();
}

class _SignInWithPhoneScreenState extends State<SignInWithPhoneScreen> {
  final AuthService _authService = AuthService();
  final FocusNode _phoneFocus = FocusNode();

  String? _phoneError;
  String _fullPhoneNumber = '';
  bool _isLoading = false;
  bool _didNavigate = false;

  @override
  void dispose() {
    _phoneFocus.dispose();
    super.dispose();
  }

  String? _validatePhone(String value) {
    if (value.trim().isEmpty) {
      return 'Phone number is required';
    }
    if (!RegExp(r'^\+\d{10,15}$').hasMatch(value.trim())) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  Future<void> _continueWithPhone() async {
    if (_isLoading) return;
    final error = _validatePhone(_fullPhoneNumber);
    setState(() {
      _phoneError = error;
    });

    if (error != null) return;

    setState(() {
      _isLoading = true;
      _didNavigate = false;
    });

    await _authService.verifyPhoneNumber(
      phoneNumber: _fullPhoneNumber,
      verificationCompleted: (credential) async {
        if (_didNavigate) return;
        _didNavigate = true;
        await _authService.signInWithCredential(credential);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) =>
                const AuthGatewayScreen(reloadUserBeforeResolve: true),
          ),
          (route) => false,
        );
      },
      codeSent: (verificationId, resendToken) async {
        if (_didNavigate || !mounted) return;
        _didNavigate = true;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerificationScreen(
              phoneNumber: _fullPhoneNumber,
              verificationId: verificationId,
              resendToken: resendToken,
              flow: PhoneAuthFlow.signIn,
            ),
          ),
        );
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _didNavigate = false;
        });
      },
      verificationFailed: (message) async {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        AppSnackbar.showError(context, message);
      },
    );

    if (mounted && !_didNavigate) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < 380;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFFFFCF8),
                  AppColors.background,
                  Color(0xFFFDF4ED),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return IgnorePointer(
                    ignoring: _isLoading,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _isLoading ? 0.97 : 1,
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 16 : 18,
                          vertical: compact ? 12 : 16,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight:
                                constraints.maxHeight - (compact ? 24 : 32),
                          ),
                          child: Column(
                            children: [
                              SizedBox(height: compact ? 60 : 68),
                              SizedBox(
                                width: compact ? 82 : 92,
                                height: compact ? 70 : 76,
                                child: SvgPicture.asset(
                                  'assets/brand/pettxo_logo.svg',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              Transform.translate(
                                offset: const Offset(0, -8),
                                child: Text(
                                  'Pettxo',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: compact ? 28 : 30,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.8,
                                  ),
                                ),
                              ),
                              SizedBox(height: compact ? 0 : 4),
                              Text(
                                'Welcome back',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textDark,
                                  fontSize: compact ? 28 : 30,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.2,
                                  height: 1.02,
                                ),
                              ),
                              SizedBox(height: compact ? 12 : 14),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 6 : 8,
                                ),
                                child: Text(
                                  'Sign in with your phone number to continue.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: const Color(0xFF958E88),
                                    fontSize: compact ? 15 : 16,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              SizedBox(height: compact ? 28 : 32),
                              _PhoneSignInField(
                                focusNode: _phoneFocus,
                                errorText: _phoneError,
                                textInputAction: TextInputAction.done,
                                onChanged: (value) {
                                  setState(() {
                                    _fullPhoneNumber = value.trim();
                                    _phoneError = _validatePhone(
                                      _fullPhoneNumber,
                                    );
                                  });
                                },
                                onSubmitted: (_) => _continueWithPhone(),
                              ),
                              SizedBox(height: compact ? 16 : 18),
                              _PhoneAuthPrimaryButton(
                                label: _isLoading
                                    ? 'Sending code...'
                                    : 'Continue',
                                compact: compact,
                                isLoading: _isLoading,
                                onPressed: _isLoading
                                    ? null
                                    : _continueWithPhone,
                              ),
                              SizedBox(height: compact ? 10 : 12),
                              _PhoneAuthSecondaryButton(
                                label: 'Continue with email',
                                compact: compact,
                                onPressed: () => Navigator.pop(context),
                              ),
                              SizedBox(height: compact ? 20 : 22),
                              Padding(
                                padding: EdgeInsets.only(
                                  bottom: compact ? 6 : 8,
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'New to Pettxo? ',
                                      style: TextStyle(
                                        color: const Color(0xFF958E88),
                                        fontSize: compact ? 15 : 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.pushReplacementNamed(
                                          context,
                                          '/signup',
                                        );
                                      },
                                      child: Text(
                                        'Create account',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontSize: compact ? 15 : 16,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneSignInField extends StatefulWidget {
  const _PhoneSignInField({
    this.focusNode,
    this.errorText,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final FocusNode? focusNode;
  final String? errorText;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_PhoneSignInField> createState() => _PhoneSignInFieldState();
}

class _PhoneSignInFieldState extends State<_PhoneSignInField> {
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _isFocused = _focusNode.hasFocus;
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (_isFocused == _focusNode.hasFocus) return;
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.errorText != null
        ? const Color(0xFFE16A6A)
        : (_isFocused ? AppColors.primary : const Color(0xFFE7E1DB));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderColor,
              width: _isFocused ? 1.5 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(
                  alpha: _isFocused ? 0.08 : 0.03,
                ),
                blurRadius: _isFocused ? 24 : 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.5),
            child: IntlPhoneField(
              focusNode: _focusNode,
              initialCountryCode: 'IN',
              textInputAction: widget.textInputAction,
              disableLengthCheck: true,
              dropdownDecoration: const BoxDecoration(color: Colors.white),
              dropdownIconPosition: IconPosition.trailing,
              flagsButtonPadding: const EdgeInsets.only(left: 10),
              showDropdownIcon: true,
              invalidNumberMessage: 'Enter a valid phone number',
              pickerDialogStyle: PickerDialogStyle(
                backgroundColor: Colors.white,
                searchFieldInputDecoration: InputDecoration(
                  hintText: 'Search country',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFDADADA)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFFDADADA)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
              decoration: InputDecoration(
                hintText: 'Phone number',
                errorText: widget.errorText,
                counterText: '',
                filled: true,
                fillColor: Colors.white,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
                hintStyle: const TextStyle(
                  color: Color(0xFFAAA39C),
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                errorStyle: const TextStyle(
                  color: Color(0xFFC94B4B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              dropdownTextStyle: const TextStyle(
                color: AppColors.textDark,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              onChanged: (phone) =>
                  widget.onChanged?.call(phone.completeNumber),
              onSubmitted: widget.onSubmitted,
            ),
          ),
        ),
      ],
    );
  }
}

class _PhoneAuthPrimaryButton extends StatelessWidget {
  const _PhoneAuthPrimaryButton({
    required this.label,
    required this.compact,
    required this.isLoading,
    required this.onPressed,
  });

  final String label;
  final bool compact;
  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 62 : 66,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: isLoading
              ? const LinearGradient(
                  colors: [Color(0xFFFFB9A5), Color(0xFFFDA184)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : AppColors.brandGradient,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(
                alpha: isLoading ? 0.12 : 0.2,
              ),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: Center(
              child: isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          label,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: compact ? 15.5 : 16.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 16 : 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneAuthSecondaryButton extends StatelessWidget {
  const _PhoneAuthSecondaryButton({
    required this.label,
    required this.compact,
    required this.onPressed,
  });

  final String label;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 62 : 66,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          backgroundColor: Colors.white.withValues(alpha: 0.74),
          padding: EdgeInsets.zero,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: AppColors.primary,
            fontSize: compact ? 16 : 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ),
    );
  }
}
