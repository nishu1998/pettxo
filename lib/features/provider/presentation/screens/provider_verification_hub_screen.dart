import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../data/repositories/provider_onboarding_repository.dart';
import '../../domain/models/provider_onboarding_models.dart';
import 'provider_bank_details_screen.dart';
import 'provider_verification_screen.dart';

class ProviderVerificationHubScreen extends StatefulWidget {
  const ProviderVerificationHubScreen({super.key});

  @override
  State<ProviderVerificationHubScreen> createState() =>
      _ProviderVerificationHubScreenState();
}

class _ProviderVerificationHubScreenState
    extends State<ProviderVerificationHubScreen> {
  final ProviderOnboardingRepository _repository =
      ProviderOnboardingRepository();

  ProviderOnboardingSnapshot? _snapshot;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _repository.syncServicesForCurrentVerificationStatus();
      final snapshot = await _repository.fetchCurrentOnboarding();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
        _loadError = null;
      });
    } catch (_) {
      try {
        final verification = await _repository.fetchCurrentVerification();
        final bankDetails = await _repository.fetchCurrentBankDetails();
        if (!mounted) return;

        if (verification.isPending) {
          setState(() {
            _snapshot = ProviderOnboardingSnapshot(
              verification: verification,
              bankDetails: bankDetails,
              hasListedService: false,
            );
            _isLoading = false;
            _loadError = null;
          });
          return;
        }
      } catch (_) {
        // Fall back to the generic load state below when the lightweight
        // verification recovery check also fails.
      }

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError =
            'Your verification is not approved yet. It is currently under review.';
      });
    }
  }

  Future<void> _openVerification() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProviderVerificationScreen()),
    );
    if (mounted) {
      setState(() => _isLoading = true);
      await _load();
    }
  }

  Future<void> _openBankDetails() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProviderBankDetailsScreen()),
    );
    if (mounted) {
      setState(() => _isLoading = true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Provider Verification & Bank Details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _loadError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SecondaryButton(
                      label: 'Try Again',
                      onPressed: _load,
                      expand: false,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              children: [
                _HubCard(
                  title: 'Verification status',
                  body: snapshot!.verification.statusMessage,
                  footer: _verificationFooter(context, snapshot),
                  actionLabel:
                      snapshot.verification.isRejected ||
                          !snapshot.verification.isSubmitted
                      ? 'Submit Documents'
                      : 'View Verification',
                  onTap: _openVerification,
                ),
                const SizedBox(height: 16),
                _HubCard(
                  title: 'Bank details',
                  body: snapshot.bankDetails.isSubmitted
                      ? 'Current payout account: ${snapshot.bankDetails.accountNumberMasked}'
                      : 'Add or update the bank account used for provider payouts.',
                  footer: snapshot.bankDetails.ifscCode.isEmpty
                      ? ''
                      : 'IFSC: ${snapshot.bankDetails.ifscCode}',
                  actionLabel: snapshot.bankDetails.isSubmitted
                      ? 'Update Bank Details'
                      : 'Add Bank Details',
                  onTap: _openBankDetails,
                ),
              ],
            ),
    );
  }

  String _verificationFooter(
    BuildContext context,
    ProviderOnboardingSnapshot snapshot,
  ) {
    final verification = snapshot.verification;
    final lines = <String>[];

    if (verification.gracePeriodEndsAt != null) {
      lines.add(
        verification.graceExpired
            ? 'Grace period ended on ${_formatDateTime(context, verification.gracePeriodEndsAt!)}.'
            : 'Grace period active until ${_formatDateTime(context, verification.gracePeriodEndsAt!)}.',
      );
    }

    if (verification.graceExpired && !verification.isApproved) {
      lines.add(
        'Your services are paused until provider verification is approved.',
      );
    } else if (verification.isPending) {
      lines.add('Your services are active while verification is under review.');
    }

    if (verification.isRejected && verification.rejectionReason.isNotEmpty) {
      lines.add('Reason: ${verification.rejectionReason}');
    }

    return lines.join('\n');
  }

  String _formatDateTime(BuildContext context, DateTime value) {
    final localDate = value.toLocal();
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(localDate);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(localDate),
    );
    return '$date at $time';
  }
}

class _HubCard extends StatelessWidget {
  final String title;
  final String body;
  final String footer;
  final String actionLabel;
  final VoidCallback onTap;

  const _HubCard({
    required this.title,
    required this.body,
    required this.footer,
    required this.actionLabel,
    required this.onTap,
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(color: AppColors.textDark, height: 1.45),
          ),
          if (footer.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              footer,
              style: const TextStyle(color: AppColors.textGrey, height: 1.45),
            ),
          ],
          const SizedBox(height: 16),
          SecondaryButton(label: actionLabel, onPressed: onTap),
        ],
      ),
    );
  }
}
