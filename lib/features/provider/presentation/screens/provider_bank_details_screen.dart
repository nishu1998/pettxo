import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/policy_link_service.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/legal_consent_checkbox.dart';
import '../../../auth/data/services/user_service.dart';
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
  final UserService _userService = UserService();
  final TextEditingController _accountHolderController =
      TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();
  final TextEditingController _confirmAccountNumberController =
      TextEditingController();
  final TextEditingController _ifscController = TextEditingController();
  final TextEditingController _upiController = TextEditingController();
  final TextEditingController _confirmUpiController = TextEditingController();

  bool _isLoading = true;
  bool _isSavingBank = false;
  bool _isSavingUpi = false;
  bool _isSavingPreferred = false;
  bool _acceptedProviderAgreement = false;
  bool _hasStoredProviderAgreement = false;
  String _selectedEditor = 'BANK_ACCOUNT';
  String _accountType = 'SAVINGS';
  String? _selectedPreferredMethod;
  String? _loadError;
  String? _consentError;
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
    _confirmUpiController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repository.fetchCurrentBankDetails(forceServer: true),
        _userService.hasAcceptedProviderAgreement(),
      ]);
      final bankDetails = results[0] as ProviderBankDetailsRecord;
      final hasAcceptedProviderAgreement = results[1] as bool;
      if (!mounted) return;
      _bankDetails = bankDetails;
      _hasStoredProviderAgreement = hasAcceptedProviderAgreement;
      _accountHolderController.text = bankDetails.accountHolderName;
      _bankNameController.text = bankDetails.bankName;
      _ifscController.text = bankDetails.ifscCode;
      _accountType = bankDetails.accountType.isEmpty
          ? 'SAVINGS'
          : bankDetails.accountType;
      _selectedPreferredMethod = bankDetails.preferredPayoutMethod.isEmpty
          ? null
          : bankDetails.preferredPayoutMethod;
      _accountNumberController.clear();
      _confirmAccountNumberController.clear();
      _upiController.clear();
      _confirmUpiController.clear();
      setState(() {
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'We could not load your payout details right now.';
      });
    }
  }

  Future<bool> _ensureAgreementAccepted() async {
    if (_hasStoredProviderAgreement) return true;
    if (_acceptedProviderAgreement) {
      setState(() => _consentError = null);
      await _userService.acceptProviderAgreementIfNeeded();
      _hasStoredProviderAgreement = true;
      return true;
    }
    setState(() {
      _consentError = 'You must agree to the Service Provider Agreement.';
    });
    return false;
  }

  Future<void> _saveBank() async {
    if (_isSavingBank) return;

    final accountHolderName = _accountHolderController.text.trim();
    final bankName = _bankNameController.text.trim();
    final accountNumber = _normalizedAccountNumber(
      _accountNumberController.text,
    );
    final confirmAccountNumber = _normalizedAccountNumber(
      _confirmAccountNumberController.text,
    );
    final ifscCode = _normalizedIfsc(_ifscController.text);

    if (accountHolderName.isEmpty) {
      _showInfo('Enter the account holder name.');
      return;
    }
    if (bankName.isEmpty) {
      _showInfo('Enter the bank name.');
      return;
    }
    if (!_isValidAccountNumber(accountNumber)) {
      _showInfo('Enter a valid account number.');
      return;
    }
    if (accountNumber != confirmAccountNumber) {
      _showInfo('Account numbers do not match.');
      return;
    }
    if (!_isValidIfsc(ifscCode)) {
      _showInfo('Enter a valid IFSC code.');
      return;
    }
    if (!await _ensureAgreementAccepted()) return;

    setState(() => _isSavingBank = true);
    try {
      await _repository.saveBankDetails(
        accountHolderName: accountHolderName,
        bankName: bankName,
        accountNumber: accountNumber,
        ifscCode: ifscCode,
        accountType: _accountType,
      );
      await _load();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Bank account saved securely.',
        tone: AppFeedbackTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not save your bank account right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingBank = false);
      }
    }
  }

  Future<void> _saveUpi() async {
    if (_isSavingUpi) return;

    final upiId = _normalizedUpi(_upiController.text);
    final confirmUpiId = _normalizedUpi(_confirmUpiController.text);

    if (!_isValidUpi(upiId)) {
      _showInfo('Enter a valid UPI ID.');
      return;
    }
    if (upiId != confirmUpiId) {
      _showInfo('UPI IDs do not match.');
      return;
    }
    if (!await _ensureAgreementAccepted()) return;

    setState(() => _isSavingUpi = true);
    try {
      await _repository.saveUpiDetails(upiId: upiId);
      await _load();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'UPI ID saved securely.',
        tone: AppFeedbackTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not save your UPI ID right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingUpi = false);
      }
    }
  }

  Future<void> _savePreferredMethod() async {
    final details = _bankDetails;
    final selected = _selectedPreferredMethod;
    if (_isSavingPreferred || details == null || selected == null) return;
    if (selected == 'BANK_ACCOUNT' && !details.hasBankAccount) {
      _showInfo('Add a bank account before selecting it.');
      return;
    }
    if (selected == 'UPI' && !details.hasUpi) {
      _showInfo('Add a UPI ID before selecting it.');
      return;
    }

    setState(() => _isSavingPreferred = true);
    try {
      await _repository.setPreferredPayoutMethod(selected);
      await _load();
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Preferred payout method updated.',
        tone: AppFeedbackTone.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'We could not update the preferred payout method.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingPreferred = false);
      }
    }
  }

  void _showInfo(String message) {
    AppFeedback.show(context, message: message, tone: AppFeedbackTone.info);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final details = _bankDetails;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Payout Details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _PayoutErrorState(message: _loadError!, onRetry: _load)
          : ListView(
              padding: EdgeInsets.fromLTRB(18, 12, 18, 24 + bottomInset),
              children: [
                _PayoutStatusCard(details: details!),
                if (details.hasLegacyDataNeedingMigration) ...[
                  const SizedBox(height: 16),
                  _InfoCard(
                    title: 'Action needed',
                    body:
                        'We preserved any older payout setup we could. Please re-enter your bank account number to finish securing future payouts.',
                  ),
                ],
                const SizedBox(height: 16),
                _MethodSelector(
                  selectedMethod: _selectedEditor,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedEditor = value);
                  },
                ),
                const SizedBox(height: 16),
                if (_selectedEditor == 'BANK_ACCOUNT')
                  _buildBankSection(details)
                else
                  _buildUpiSection(details),
                if (details.hasBankAccount && details.hasUpi) ...[
                  const SizedBox(height: 16),
                  _buildPreferredMethodSection(details),
                ],
                if (!_hasStoredProviderAgreement) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: _cardDecoration(),
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
              ],
            ),
    );
  }

  Widget _buildBankSection(ProviderBankDetailsRecord details) {
    final hasConfiguredBank = details.hasBankAccount;
    final maskedAccount = details.accountNumberMasked;
    final buttonLabel = hasConfiguredBank
        ? 'Update Bank Account'
        : 'Save Bank Account';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bank Account',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasConfiguredBank
                ? 'Current account on file: $maskedAccount'
                : details.hasLegacyDataNeedingMigration &&
                      maskedAccount.isNotEmpty
                ? 'Older payout setup found: $maskedAccount. Re-enter the full account number to secure it.'
                : 'Add the bank account we should use for manual provider payouts.',
            style: const TextStyle(color: AppColors.textGrey, height: 1.45),
          ),
          const SizedBox(height: 10),
          const Text(
            'For security, full account numbers are never shown back in the app after you save them.',
            style: TextStyle(color: AppColors.textGrey, height: 1.45),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _accountHolderController,
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration('Account holder name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bankNameController,
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration('Bank name'),
          ),
          const SizedBox(height: 14),
          _SegmentedChoiceRow(
            label: 'Account type',
            selected: _accountType,
            options: const ['SAVINGS', 'CURRENT'],
            onChanged: (value) => setState(() => _accountType = value),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _accountNumberController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _fieldDecoration(
              hasConfiguredBank ? 'New account number' : 'Account number',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirmAccountNumberController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _fieldDecoration('Confirm account number'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ifscController,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
            ],
            decoration: _fieldDecoration('IFSC code'),
          ),
          const SizedBox(height: 18),
          GradientButton(
            label: buttonLabel,
            onPressed: _isSavingBank ? null : _saveBank,
          ),
        ],
      ),
    );
  }

  Widget _buildUpiSection(ProviderBankDetailsRecord details) {
    final hasConfiguredUpi = details.hasUpi;
    final maskedUpi = details.upiId;
    final buttonLabel = hasConfiguredUpi ? 'Update UPI ID' : 'Save UPI ID';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'UPI',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasConfiguredUpi
                ? 'Current UPI on file: $maskedUpi'
                : 'Add a UPI ID if you want Pettxo payouts routed through UPI.',
            style: const TextStyle(color: AppColors.textGrey, height: 1.45),
          ),
          const SizedBox(height: 10),
          const Text(
            'If you replace the UPI ID, enter the new one again for confirmation before saving.',
            style: TextStyle(color: AppColors.textGrey, height: 1.45),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _upiController,
            keyboardType: TextInputType.emailAddress,
            decoration: _fieldDecoration(
              hasConfiguredUpi ? 'New UPI ID' : 'UPI ID',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _confirmUpiController,
            keyboardType: TextInputType.emailAddress,
            decoration: _fieldDecoration('Confirm UPI ID'),
          ),
          const SizedBox(height: 18),
          GradientButton(
            label: buttonLabel,
            onPressed: _isSavingUpi ? null : _saveUpi,
          ),
        ],
      ),
    );
  }

  Widget _buildPreferredMethodSection(ProviderBankDetailsRecord details) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preferred payout method',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose which configured payout method Pettxo should use by default for manual settlements.',
            style: TextStyle(color: AppColors.textGrey, height: 1.45),
          ),
          const SizedBox(height: 18),
          _SegmentedChoiceRow(
            label: 'Preferred method',
            selected: _selectedPreferredMethod ?? details.preferredPayoutMethod,
            options: const ['BANK_ACCOUNT', 'UPI'],
            onChanged: (value) =>
                setState(() => _selectedPreferredMethod = value),
          ),
          const SizedBox(height: 18),
          SecondaryButton(
            label: 'Save Preferred Method',
            onPressed: _isSavingPreferred ? null : _savePreferredMethod,
            expand: true,
          ),
        ],
      ),
    );
  }

  String _normalizedAccountNumber(String input) =>
      input.replaceAll(RegExp(r'\s+'), '').trim();

  String _normalizedIfsc(String input) =>
      input.replaceAll(RegExp(r'\s+'), '').trim().toUpperCase();

  String _normalizedUpi(String input) =>
      input.replaceAll(RegExp(r'\s+'), '').trim().toLowerCase();

  bool _isValidAccountNumber(String value) =>
      RegExp(r'^\d{6,20}$').hasMatch(value);

  bool _isValidIfsc(String value) =>
      RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(value);

  bool _isValidUpi(String value) =>
      RegExp(r'^[a-z0-9._-]{2,256}@[a-z]{2,64}$').hasMatch(value);
}

class _PayoutStatusCard extends StatelessWidget {
  const _PayoutStatusCard({required this.details});

  final ProviderBankDetailsRecord details;

  @override
  Widget build(BuildContext context) {
    final configuredMethods = <String>[
      if (details.hasBankAccount) 'Bank account',
      if (details.hasUpi) 'UPI',
    ];
    final summaryText = configuredMethods.isEmpty
        ? 'No payout method is configured yet.'
        : 'Configured methods: ${configuredMethods.join(' + ')}';
    final preferredText = details.preferredPayoutMethod.isEmpty
        ? 'Preferred method will be set automatically after you add a payout destination.'
        : 'Preferred: ${details.preferredPayoutMethod == 'BANK_ACCOUNT' ? 'Bank account' : 'UPI'}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
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
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  details.configurationLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
            summaryText,
            style: const TextStyle(color: AppColors.textGrey, height: 1.45),
          ),
          const SizedBox(height: 6),
          Text(
            preferredText,
            style: const TextStyle(color: AppColors.textGrey, height: 1.45),
          ),
          if (details.accountNumberMasked.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Bank: ${details.bankName.isEmpty ? 'Account on file' : details.bankName} • ${details.accountNumberMasked}',
              style: const TextStyle(color: AppColors.textGrey, height: 1.45),
            ),
          ],
          if (details.upiId.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'UPI: ${details.upiId}',
              style: const TextStyle(color: AppColors.textGrey, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

class _MethodSelector extends StatelessWidget {
  const _MethodSelector({
    required this.selectedMethod,
    required this.onChanged,
  });

  final String selectedMethod;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _MethodPill(
            label: 'Bank Account',
            selected: selectedMethod == 'BANK_ACCOUNT',
            onTap: () => onChanged('BANK_ACCOUNT'),
          ),
          const SizedBox(width: 8),
          _MethodPill(
            label: 'UPI',
            selected: selectedMethod == 'UPI',
            onTap: () => onChanged('UPI'),
          ),
        ],
      ),
    );
  }
}

class _MethodPill extends StatelessWidget {
  const _MethodPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : const Color(0xFFFFFAF7),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentedChoiceRow extends StatelessWidget {
  const _SegmentedChoiceRow({
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String selected;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: options.map((option) {
            final selectedOption = selected == option;
            return ChoiceChip(
              label: Text(
                option == 'BANK_ACCOUNT'
                    ? 'Bank account'
                    : option == 'SAVINGS'
                    ? 'Savings'
                    : option == 'CURRENT'
                    ? 'Current'
                    : option,
              ),
              selected: selectedOption,
              onSelected: (_) => onChanged(option),
              selectedColor: AppColors.primary.withValues(alpha: 0.16),
              backgroundColor: const Color(0xFFFFFAF7),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: selectedOption ? AppColors.textDark : AppColors.textGrey,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(
                color: selectedOption
                    ? AppColors.primary.withValues(alpha: 0.30)
                    : Colors.transparent,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: AppColors.textGrey, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _PayoutErrorState extends StatelessWidget {
  const _PayoutErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

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

InputDecoration _fieldDecoration(String label) {
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

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
  );
}
