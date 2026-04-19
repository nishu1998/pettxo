import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';

import '../../../../core/constants/app_colors.dart';

class CommonPhoneField extends StatefulWidget {
  final String labelText;
  final String? initialNumber;
  final String? errorText;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const CommonPhoneField({
    super.key,
    this.labelText = 'Phone Number',
    this.initialNumber,
    this.errorText,
    this.focusNode,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<CommonPhoneField> createState() => _CommonPhoneFieldState();
}

class _CommonPhoneFieldState extends State<CommonPhoneField> {
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
    const borderRadius = 12.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  blurRadius: 16,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: IntlPhoneField(
        focusNode: _focusNode,
        initialCountryCode: 'IN',
        initialValue: widget.initialNumber,
        textInputAction: widget.textInputAction,
        disableLengthCheck: true,
        dropdownDecoration: const BoxDecoration(color: Colors.white),
        dropdownIconPosition: IconPosition.trailing,
        flagsButtonPadding: const EdgeInsets.only(left: 12),
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
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(color: Color(0xFFDADADA)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(color: Color(0xFFDADADA)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.4,
              ),
            ),
          ),
        ),
        decoration: InputDecoration(
          labelText: widget.labelText,
          errorText: widget.errorText,
          counterText: '',
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            borderSide: const BorderSide(color: Color(0xFFDADADA)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            borderSide: const BorderSide(color: Color(0xFFDADADA)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            borderSide: const BorderSide(color: Colors.redAccent),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(borderRadius),
            borderSide: const BorderSide(color: Colors.redAccent, width: 1.8),
          ),
          labelStyle: const TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w500,
          ),
        ),
        onChanged: (phone) => widget.onChanged?.call(phone.completeNumber),
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}
