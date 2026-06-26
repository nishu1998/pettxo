import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../data/repositories/provider_onboarding_repository.dart';
import '../../domain/models/provider_onboarding_models.dart';

class ProviderBankDetailsScreen extends StatefulWidget {
  const ProviderBankDetailsScreen({super.key});

  @override
  State<ProviderBankDetailsScreen> createState() =>
      _ProviderBankDetailsScreenState();
}

class _ProviderBankDetailsScreenState extends State<ProviderBankDetailsScreen> {
  final ProviderOnboardingRepository _repository =
      ProviderOnboardingRepository();
  final TextEditingController _accountHolderController =
      TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();
  final TextEditingController _confirmAccountNumberController =
      TextEditingController();
  final TextEditingController _ifscController = TextEditingController();
  final TextEditingController _upiController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;
  ProviderBankDetailsRecord? _bankDetails;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _accountHolderController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _confirmAccountNumberController.dispose();
    _ifscController.dispose();
    _upiController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bankDetails = await _repository.fetchCurrentBankDetails();
      if (!mounted) return;
      _bankDetails = bankDetails;
      _accountHolderController.text = bankDetails.accountHolderName;
      _bankNameController.text = bankDetails.bankName;
      _accountNumberController.clear();
      _confirmAccountNumberController.clear();
      _ifscController.text = bankDetails.ifscCode;
      _upiController.text = bankDetails.upiId;
      setState(() {
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'We could not load your bank details right now.';
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final accountHolderName = _accountHolderController.text.trim();
    final bankName = _bankNameController.text.trim();
    final accountNumber = _accountNumberController.text.trim();
    final confirmAccountNumber = _confirmAccountNumberController.text.trim();
    final ifscCode = _ifscController.text.trim().toUpperCase();
    final upiId = _upiController.text.trim();

    if (accountHolderName.isEmpty) {
      _showInfo('Enter the account holder name.');
      return;
    }
    if (bankName.isEmpty) {
      _showInfo('Enter the bank name.');
      return;
    }
    if (accountNumber.length < 6) {
      _showInfo('Enter a valid account number.');
      return;
    }
    if (accountNumber != confirmAccountNumber) {
      _showInfo('Account numbers do not match.');
      return;
    }
    if (!RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(ifscCode)) {
      _showInfo('Enter a valid IFSC code.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _repository.saveBankDetails(
        accountHolderName: accountHolderName,
        bankName: bankName,
        accountNumber: accountNumber,
        ifscCode: ifscCode,
        upiId: upiId,
      );
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Bank details saved successfully.',
        tone: AppFeedbackTone.success,
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not save your bank details right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showInfo(String message) {
    AppFeedback.show(context, message: message, tone: AppFeedbackTone.info);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Provider Bank Details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _BankErrorState(message: _loadError!, onRetry: _load)
          : ListView(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 24 + bottomInset),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Payout setup',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _bankDetails?.accountNumberMasked.isNotEmpty == true
                            ? 'Current account on file: ${_bankDetails!.accountNumberMasked}'
                            : 'Add your payout account so we can send provider earnings securely.',
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'For security, Pettxo only keeps the masked account number visible in the app after you save it.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _accountHolderController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _bankFieldDecoration('Account holder name'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _bankNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: _bankFieldDecoration('Bank name'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _accountNumberController,
                        keyboardType: TextInputType.number,
                        decoration: _bankFieldDecoration('Account number'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _confirmAccountNumberController,
                        keyboardType: TextInputType.number,
                        decoration: _bankFieldDecoration(
                          'Confirm account number',
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _ifscController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: _bankFieldDecoration('IFSC code'),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _upiController,
                        decoration: _bankFieldDecoration('UPI ID (optional)'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                GradientButton(
                  label: _bankDetails?.isSubmitted == true
                      ? 'Update Bank Details'
                      : 'Save Bank Details',
                  onPressed: _isSaving ? null : _save,
                ),
              ],
            ),
    );
  }
}

class _BankErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _BankErrorState({required this.message, required this.onRetry});

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

InputDecoration _bankFieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFFFFAF7),
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
      borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
    ),
  );
}
