import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/policy_link_service.dart';

class LegalPolicyDocument {
  final String title;
  final String routeName;
  final String remoteConfigKey;
  final IconData icon;
  final List<String> paragraphs;

  const LegalPolicyDocument({
    required this.title,
    required this.routeName,
    required this.remoteConfigKey,
    required this.icon,
    required this.paragraphs,
  });
}

class LegalPoliciesCatalog {
  const LegalPoliciesCatalog._();

  static const cancellationPolicy = LegalPolicyDocument(
    title: 'Cancellation Policy',
    routeName: '/settings/legal/cancellation-policy',
    remoteConfigKey: PolicyLinkService.cancellationPolicyKey,
    icon: Icons.event_busy_outlined,
    paragraphs: [
      'Free cancellation is available within 30 minutes of booking confirmation.',
      'After the free-cancellation window, refund eligibility depends on how close the cancellation is to the scheduled service time.',
      'If the provider does not respond within 24 hours, or before 1 hour of service start, whichever comes first, the request expires automatically.',
      'Approved refunds are processed back to the original payment method according to the payment partner timeline.',
    ],
  );

  static const refundPolicy = LegalPolicyDocument(
    title: 'Refund Policy',
    routeName: '/settings/legal/refund-policy',
    remoteConfigKey: PolicyLinkService.refundPolicyKey,
    icon: Icons.currency_rupee_rounded,
    paragraphs: [
      'Eligible refunds are calculated after any applicable cancellation charges, service fees, or offer adjustments.',
      'If a provider cannot fulfill a confirmed booking, Pettxo will initiate the applicable refund automatically.',
      'Refund timelines depend on your bank, card network, or wallet provider after Pettxo marks the refund as processed.',
    ],
  );

  static const termsAndConditions = LegalPolicyDocument(
    title: 'Terms & Conditions',
    routeName: '/settings/legal/terms-and-conditions',
    remoteConfigKey: PolicyLinkService.termsConditionsKey,
    icon: Icons.description_outlined,
    paragraphs: [
      'Using Pettxo means you agree to provide accurate account details, respectful communication, and lawful use of the platform.',
      'Bookings, messages, offers, and provider tools are subject to platform eligibility, moderation, and safety checks.',
      'Pettxo may update operational rules and notify users when important policy or product changes are made.',
    ],
  );

  static const privacyPolicy = LegalPolicyDocument(
    title: 'Privacy Policy',
    routeName: '/settings/legal/privacy-policy',
    remoteConfigKey: PolicyLinkService.privacyPolicyKey,
    icon: Icons.privacy_tip_outlined,
    paragraphs: [
      'Pettxo collects account, booking, and device information needed to deliver platform features securely.',
      'Personal data is used for authentication, service delivery, notifications, moderation, and support operations.',
      'Users can review and update important profile information from within the app settings and account flows.',
    ],
  );

  static const providerPolicy = LegalPolicyDocument(
    title: 'Provider Policy',
    routeName: '/settings/legal/provider-policy',
    remoteConfigKey: PolicyLinkService.providerPolicyKey,
    icon: Icons.verified_user_outlined,
    paragraphs: [
      'Providers must maintain accurate listings, honor accepted bookings, and keep verification and payout information up to date.',
      'Services may be paused or hidden if verification expires, moderation actions apply, or trust and safety checks fail.',
      'Provider payouts, disputes, and service-quality expectations follow the latest Pettxo provider operations policy.',
    ],
  );

  static const documents = [
    cancellationPolicy,
    refundPolicy,
    termsAndConditions,
    privacyPolicy,
    providerPolicy,
  ];
}

class LegalPoliciesScreen extends StatelessWidget {
  const LegalPoliciesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.background,
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
                      'Legal & Policies',
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
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < LegalPoliciesCatalog.documents.length;
                    index++
                  ) ...[
                    _PolicyTile(
                      document: LegalPoliciesCatalog.documents[index],
                    ),
                    if (index != LegalPoliciesCatalog.documents.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LegalPolicyDetailScreen extends StatelessWidget {
  final LegalPolicyDocument document;

  const LegalPolicyDetailScreen({super.key, required this.document});

  Future<void> _openFullPolicy(BuildContext context) async {
    final opened = await PolicyLinkService.openExternalPolicyUrl(
      document.remoteConfigKey,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open policy link. Please try again later.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      document.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFFFF2EA),
                        child: Icon(document.icon, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          document.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  for (final paragraph in document.paragraphs) ...[
                    _PolicyBullet(text: paragraph),
                    const SizedBox(height: 12),
                  ],
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => _openFullPolicy(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Read full policy on website',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyTile extends StatelessWidget {
  final LegalPolicyDocument document;

  const _PolicyTile({required this.document});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFFFF2EA),
        child: Icon(document.icon, color: AppColors.primary),
      ),
      title: Text(
        document.title,
        style: const TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.primary,
      ),
      onTap: () => Navigator.pushNamed(context, document.routeName),
    );
  }
}

class _PolicyBullet extends StatelessWidget {
  final String text;

  const _PolicyBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 6),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.textDark,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
