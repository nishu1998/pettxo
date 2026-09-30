import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/policy_link_service.dart';
import '../../../../core/widgets/app_snackbar.dart';

class LegalPolicyDocument {
  final String title;
  final String routeName;
  final String remoteConfigKey;
  final IconData icon;
  final List<LegalPolicyItem> items;

  const LegalPolicyDocument({
    required this.title,
    required this.routeName,
    required this.remoteConfigKey,
    required this.icon,
    required this.items,
  });
}

class LegalPolicyItem {
  final String text;
  final List<String> details;

  const LegalPolicyItem(this.text, {this.details = const []});
}

class LegalPoliciesCatalog {
  const LegalPoliciesCatalog._();

  static const cancellationPolicy = LegalPolicyDocument(
    title: 'Cancellation Policy',
    routeName: '/settings/legal/cancellation-policy',
    remoteConfigKey: PolicyLinkService.cancellationPolicyKey,
    icon: Icons.event_busy_outlined,
    items: [
      LegalPolicyItem(
        'You can cancel a booking request for free at any time before you pay. Nothing is charged until payment.',
      ),
      LegalPolicyItem(
        'After payment, your refund depends on how much time is left before the service starts:',
        details: [
          'More than 24 hours before: 95% back',
          '12 to 24 hours before: 75% back',
          '6 to 12 hours before: 50% back',
          '2 to 6 hours before: 25% back',
          'Less than 2 hours before: no refund',
        ],
      ),
      LegalPolicyItem(
        "Once the provider enters your OTP, the service has started and the booking can't be cancelled.",
      ),
      LegalPolicyItem(
        "If you don't show up for your booking, it is treated like a cancellation less than 2 hours before, so there is no refund.",
      ),
      LegalPolicyItem(
        'For boarding and sitting, the time is counted from your check-in time. Collecting your pet early does not give a partial refund.',
      ),
    ],
  );

  static const refundPolicy = LegalPolicyDocument(
    title: 'Refund Policy',
    routeName: '/settings/legal/refund-policy',
    remoteConfigKey: PolicyLinkService.refundPolicyKey,
    icon: Icons.currency_rupee_rounded,
    items: [
      LegalPolicyItem(
        'Your refund is calculated on the amount you actually paid, based on the cancellation timing.',
      ),
      LegalPolicyItem(
        'If the provider cancels a paid booking, you get 100% of what you paid back, automatically.',
      ),
      LegalPolicyItem(
        'Refunds go back to the account you paid from, within 5 to 7 working days.',
      ),
      LegalPolicyItem(
        'If something went wrong with your service, you can raise an issue in the app within 24 hours of the service ending. We review every case before any money is released.',
      ),
    ],
  );

  static const termsAndConditions = LegalPolicyDocument(
    title: 'Terms & Conditions',
    routeName: '/settings/legal/terms-and-conditions',
    remoteConfigKey: PolicyLinkService.termsConditionsKey,
    icon: Icons.description_outlined,
    items: [
      LegalPolicyItem(
        'Booking works in three steps. You send a request. The provider has 60 minutes to accept, counted within their working hours. You then have 60 minutes to pay. Your booking is confirmed only after payment.',
      ),
      LegalPolicyItem(
        'A service starts only when the provider enters your OTP.',
      ),
      LegalPolicyItem(
        "Bookings can't be rescheduled. To change a time, cancel and book again.",
      ),
      LegalPolicyItem(
        'Providers on Pettxo are independent. Pettxo verifies them, but they run their own services.',
      ),
      LegalPolicyItem(
        'Using Pettxo means you agree to give accurate details, communicate respectfully, and use the platform lawfully. Pettxo will notify you before important policy changes take effect.',
      ),
    ],
  );

  static const privacyPolicy = LegalPolicyDocument(
    title: 'Privacy Policy',
    routeName: '/settings/legal/privacy-policy',
    remoteConfigKey: PolicyLinkService.privacyPolicyKey,
    icon: Icons.privacy_tip_outlined,
    items: [
      LegalPolicyItem(
        'Pettxo collects account, pet, booking, and device information to run the platform.',
      ),
      LegalPolicyItem(
        'Your name and phone number are shared with a provider only after your booking is paid and confirmed.',
      ),
      LegalPolicyItem(
        'Booking activity, such as response and cancellation history, is used for safety checks and to rank providers in search.',
      ),
      LegalPolicyItem(
        'Your data is stored on servers in India. You can update your details in app settings or contact hello@pettxo.com.',
      ),
    ],
  );

  static const providerPolicy = LegalPolicyDocument(
    title: 'Provider Policy',
    routeName: '/settings/legal/provider-policy',
    remoteConfigKey: PolicyLinkService.providerPolicyKey,
    icon: Icons.verified_user_outlined,
    items: [
      LegalPolicyItem(
        'Providers are verified manually using a government ID and bank details before they can list.',
      ),
      LegalPolicyItem(
        'You have 60 minutes within your working hours to accept or decline a request. Declining is never penalised.',
      ),
      LegalPolicyItem(
        'Ignoring requests or cancelling paid bookings leads to temporary pauses. If you cancel a paid booking, the pet parent gets 100% back and you earn nothing for it.',
      ),
      LegalPolicyItem(
        'Payment for a service is released 24 hours after it ends, if no issue has been raised. If a pet parent cancels close to the service time, you get the provider share set out in the Cancellation Policy.',
      ),
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
      AppSnackbar.error(
        context,
        message: 'Unable to open policy link. Please try again later.',
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
                  for (final item in document.items) ...[
                    _PolicyBullet(item: item),
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
  final LegalPolicyItem item;

  const _PolicyBullet({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
                item.text,
                style: const TextStyle(
                  color: AppColors.textDark,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (item.details.isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Column(
              children: [
                for (var index = 0; index < item.details.length; index++) ...[
                  _PolicyDetailBullet(text: item.details[index]),
                  if (index != item.details.length - 1)
                    const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PolicyDetailBullet extends StatelessWidget {
  final String text;

  const _PolicyDetailBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final separatorIndex = text.lastIndexOf(': ');
    final timing = separatorIndex == -1
        ? text
        : text.substring(0, separatorIndex + 1);
    final refund = separatorIndex == -1
        ? ''
        : text.substring(separatorIndex + 2);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 7),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.75),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$timing${refund.isEmpty ? '' : ' '}'),
                if (refund.isNotEmpty)
                  TextSpan(
                    text: refund,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            style: const TextStyle(
              color: AppColors.textDark,
              height: 1.45,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
