import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../domain/models/booking_flow_models.dart';
import '../widgets/section_block.dart';
import '../widgets/status_chip.dart';

class BookingDetailScreen extends StatefulWidget {
  final BookingRecord booking;

  const BookingDetailScreen({super.key, required this.booking});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  late final Timer _timer;
  int _elapsedSeconds = 0;
  int _starRating = 4;
  final TextEditingController _reviewController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds += 1);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _reviewController.dispose();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String _formatCountdown(int initialSeconds) {
    final remaining = (initialSeconds - _elapsedSeconds).clamp(0, 99999);
    final minutes = remaining ~/ 60;
    final seconds = remaining % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final topContentPadding = topInset + 100;
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);
    final title = switch (widget.booking.detailType) {
      BookingDetailType.deliveringRequest => 'Booking Request',
      _ => 'Booking Details',
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              18,
              topContentPadding,
              18,
              bottomContentPadding,
            ),
            children: [
              ..._buildDetailContent(),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: topInset + 10,
            child: GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              borderRadius: BorderRadius.circular(24),
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              blurSigma: 20,
              border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bookings',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SocialBottomNav(activeTab: SocialAppTab.profile),
    );
  }

  List<Widget> _buildDetailContent() {
    switch (widget.booking.detailType) {
      case BookingDetailType.receivingConfirmed:
        return _buildReceivingConfirmed();
      case BookingDetailType.receivingRequested:
        return _buildReceivingRequested();
      case BookingDetailType.receivingCompleted:
        return _buildReceivingCompleted();
      case BookingDetailType.deliveringRequest:
        return _buildDeliveringRequest();
      case BookingDetailType.deliveringConfirmed:
        return _buildDeliveringConfirmed();
      case null:
        return [
          const SizedBox.shrink(),
        ];
    }
  }

  List<Widget> _buildReceivingConfirmed() {
    return [
      _BannerCard(
        backgroundColor: const Color(0xFFFEF3C7),
        text: 'Cancel within ${_formatCountdown(754)} for full refund',
      ),
      SectionBlock(
        title: 'SERVICE',
        rows: const [
          DetailRowData(label: 'Service', value: 'Daily Dog Walk'),
          DetailRowData(label: 'Animal', value: '🐕 Dog'),
          DetailRowData(
            label: 'Provider',
            value: 'Ravi Sharma ↗',
            valueColor: AppColors.primary,
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'SCHEDULE',
        rows: const [
          DetailRowData(label: 'Date', value: 'Tomorrow, 12 Apr'),
          DetailRowData(label: 'Time', value: '8:00 AM'),
          DetailRowData(label: 'Duration', value: '60 min'),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'STATUS',
        rows: [
          DetailRowData(
            label: 'Status',
            value: '',
            trailing: const StatusChip(
              label: 'Confirmed',
              tone: BookingStatusTone.confirmed,
            ),
          ),
          const DetailRowData(label: 'Paid', value: '₹350'),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'YOUR SERVICE OTP',
        child: _OtpDisplay(
          digits: const ['7', '4', '2', '9'],
          subtitle: 'Do not share before the provider arrives',
        ),
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'CONTACT (UNLOCKED AFTER CONFIRMATION)',
        child: const _PhoneContact(
          name: 'Ravi Sharma',
          phone: '+91 98765 43210',
        ),
      ),
      const SizedBox(height: 12),
      _DualActionRow(
        primaryLabel: 'Cancel booking',
        primaryStyle: BookingActionStyle.danger,
        secondaryLabel: 'Message',
        secondaryStyle: BookingActionStyle.secondary,
        onPrimaryTap: () => _showToast('Cancellation flow opened'),
        onSecondaryTap: () => _showToast('Messaging flow opened'),
      ),
    ];
  }

  List<Widget> _buildReceivingRequested() {
    return [
      _BannerCard(
        backgroundColor: const Color(0xFFEFF6FF),
        text:
            'Waiting for provider to confirm · Request expires in ${_formatCountdown(1123)}',
      ),
      _BannerCard(
        backgroundColor: const Color(0xFFFEF3C7),
        text: 'Full refund available for 28:43 · Grace window active',
      ),
      SectionBlock(
        title: 'SERVICE',
        rows: const [
          DetailRowData(label: 'Service', value: 'Cat Grooming Session'),
          DetailRowData(label: 'Animal', value: '🐱 Cat'),
          DetailRowData(
            label: 'Provider',
            value: 'Priya\'s Pet Salon ↗',
            valueColor: AppColors.primary,
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'SCHEDULE',
        rows: const [
          DetailRowData(label: 'Date', value: 'Sat, 19 Apr'),
          DetailRowData(label: 'Time', value: '11:00 AM'),
          DetailRowData(label: 'Duration', value: '90 min'),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'STATUS',
        rows: [
          DetailRowData(
            label: 'Status',
            value: '',
            trailing: const StatusChip(
              label: 'Awaiting confirmation',
              tone: BookingStatusTone.awaiting,
            ),
          ),
          const DetailRowData(label: 'Paid', value: '₹650'),
        ],
      ),
      const SizedBox(height: 12),
      const SectionBlock(
        title: 'CONTACT',
        backgroundColor: Color(0xFFF3F4F6),
        child: Text(
          'Phone number unlocks after the provider confirms the booking.',
          style: TextStyle(color: AppColors.textGrey, fontSize: 12.5),
        ),
      ),
      const SizedBox(height: 12),
      _DualActionRow(
        primaryLabel: 'Cancel (full refund)',
        primaryStyle: BookingActionStyle.danger,
        secondaryLabel: 'Message',
        secondaryStyle: BookingActionStyle.secondary,
        onPrimaryTap: () =>
            _showToast('100% refund available during grace window.'),
        onSecondaryTap: () => _showToast('Messaging flow opened'),
      ),
    ];
  }

  List<Widget> _buildReceivingCompleted() {
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFDCFCE7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x3315803D)),
        ),
        child: const Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: Color(0xFF15803D),
              child: Icon(Icons.check_rounded, color: Colors.white, size: 18),
            ),
            SizedBox(width: 10),
            Text(
              'Service Completed',
              style: TextStyle(
                color: Color(0xFF15803D),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'REVIEW RAVI SHARMA',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How was your experience?',
              style: TextStyle(color: AppColors.textGrey, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final isLit = index < _starRating;
                return IconButton(
                  onPressed: () => setState(() => _starRating = index + 1),
                  icon: Icon(
                    Icons.star_rounded,
                    color: isLit ? const Color(0xFFF59E0B) : const Color(0xFFD1D5DB),
                    size: 30,
                  ),
                );
              }),
            ),
            TextField(
              controller: _reviewController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Tell others about your experience...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x1A000000)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x1A000000)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _DualActionRow(
              primaryLabel: 'Submit review',
              primaryStyle: BookingActionStyle.primary,
              secondaryLabel: 'Skip',
              secondaryStyle: BookingActionStyle.secondary,
              onPrimaryTap: () => _showToast('Review submitted!'),
              onSecondaryTap: () => _showToast('Review skipped'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'SERVICE',
        rows: const [
          DetailRowData(label: 'Service', value: 'Dog Grooming Session'),
          DetailRowData(label: 'Animal', value: '🐕 Dog'),
          DetailRowData(label: 'Paid', value: '₹499'),
        ],
      ),
    ];
  }

  List<Widget> _buildDeliveringRequest() {
    return [
      _BannerCard(
        backgroundColor: const Color(0xFFFEF3C7),
        text:
            'Respond within ${_formatCountdown(1330)} · Auto-cancel if no response',
      ),
      const SectionBlock(
        title: 'PET PARENT',
        child: _IdentityRow(
          initials: 'AM',
          name: 'Anjali Mehta',
          handle: '@anjali_m',
          initialsBackground: Color(0xFFEFF6FF),
          initialsForeground: Color(0xFF1D4ED8),
        ),
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'SERVICE REQUESTED',
        rows: const [
          DetailRowData(label: 'Service', value: 'Daily Dog Walk'),
          DetailRowData(label: 'Animal', value: '🐕 Dog'),
          DetailRowData(label: 'Date', value: 'Today, 11 Apr'),
          DetailRowData(label: 'Time', value: '5:00 PM'),
          DetailRowData(label: 'Duration', value: '60 min'),
          DetailRowData(
            label: 'You earn',
            value: '₹297',
            valueColor: Color(0xFF15803D),
            valueWeight: FontWeight.w700,
          ),
        ],
      ),
      const SizedBox(height: 12),
      _DualActionRow(
        primaryLabel: 'Accept booking',
        primaryStyle: BookingActionStyle.primary,
        secondaryLabel: 'Reject',
        secondaryStyle: BookingActionStyle.danger,
        onPrimaryTap: () => _showToast('Booking accepted! Pet parent notified.'),
        onSecondaryTap: () =>
            _showToast('Booking rejected. Full refund to pet parent.'),
      ),
      const SizedBox(height: 8),
      const Text(
        'If you do not respond, the booking auto-cancels and the pet parent gets a full refund.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textGrey,
          fontSize: 11.5,
          height: 1.5,
        ),
      ),
    ];
  }

  List<Widget> _buildDeliveringConfirmed() {
    return [
      const SectionBlock(
        title: 'PET PARENT',
        child: _IdentityRow(
          initials: 'MJ',
          name: 'Meera Joshi',
          handle: '@meera_j',
          initialsBackground: Color(0xFFFEF0EB),
          initialsForeground: Color(0xFF9A3412),
        ),
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'SERVICE',
        rows: const [
          DetailRowData(label: 'Service', value: 'Dog Bath & Brush'),
          DetailRowData(label: 'Animal', value: '🐕 Dog'),
          DetailRowData(label: 'Today', value: '3:00 PM · 60 min'),
          DetailRowData(
            label: 'You earn',
            value: '₹382',
            valueColor: Color(0xFF15803D),
            valueWeight: FontWeight.w700,
          ),
        ],
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'ENTER OTP TO START SERVICE',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ask the pet parent to share their 4-digit OTP.',
              style: TextStyle(color: AppColors.textGrey, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _otpControllers.map((controller) {
                return Container(
                  width: 46,
                  height: 52,
                  margin: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0x1A000000)),
                  ),
                  alignment: Alignment.center,
                  child: TextField(
                    controller: controller,
                    maxLength: 1,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      hintText: '—',
                    ),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDark,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: GradientButton(
                label: 'Start Service',
                onPressed: () => _showToast('OTP verified! Service started.'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SectionBlock(
        title: 'CONTACT (UNLOCKED)',
        child: const _PhoneContact(
          name: 'Meera Joshi',
          phone: '+91 87654 32109',
        ),
      ),
      const SizedBox(height: 12),
      _DualActionRow(
        primaryLabel: 'Message',
        primaryStyle: BookingActionStyle.secondary,
        secondaryLabel: '',
        secondaryStyle: BookingActionStyle.secondary,
        onPrimaryTap: () => _showToast('Messaging flow opened'),
        hideSecondary: true,
      ),
    ];
  }
}

class _BannerCard extends StatelessWidget {
  final Color backgroundColor;
  final String text;

  const _BannerCard({required this.backgroundColor, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textDark,
            fontSize: 12.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _OtpDisplay extends StatelessWidget {
  final List<String> digits;
  final String subtitle;

  const _OtpDisplay({required this.digits, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF0EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFDD5C4),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          const Text(
            'Share with provider on arrival',
            style: TextStyle(
              color: Color(0xFF9A3412),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: digits.map((digit) {
              return Container(
                width: 40,
                height: 46,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDD5C4)),
                ),
                alignment: Alignment.center,
                child: Text(
                  digit,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.textGrey, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _PhoneContact extends StatelessWidget {
  final String phone;
  final String name;

  const _PhoneContact({required this.phone, required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Color(0xFFDCFCE7),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.call_rounded,
                size: 18,
                color: Color(0xFF15803D),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phone,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Tap to call $name',
                  style: const TextStyle(
                    color: Color(0xFF15803D),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Shared after confirmation. Use Pettxo chat for future bookings.',
          style: TextStyle(color: AppColors.textGrey, fontSize: 11.5),
        ),
      ],
    );
  }
}

class _IdentityRow extends StatelessWidget {
  final String initials;
  final String name;
  final String handle;
  final Color initialsBackground;
  final Color initialsForeground;

  const _IdentityRow({
    required this.initials,
    required this.name,
    required this.handle,
    required this.initialsBackground,
    required this.initialsForeground,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: initialsBackground,
          child: Text(
            initials,
            style: TextStyle(
              color: initialsForeground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            Text(
              handle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DualActionRow extends StatelessWidget {
  final String primaryLabel;
  final BookingActionStyle primaryStyle;
  final VoidCallback onPrimaryTap;
  final String secondaryLabel;
  final BookingActionStyle secondaryStyle;
  final VoidCallback? onSecondaryTap;
  final bool hideSecondary;

  const _DualActionRow({
    required this.primaryLabel,
    required this.primaryStyle,
    required this.onPrimaryTap,
    required this.secondaryLabel,
    required this.secondaryStyle,
    this.onSecondaryTap,
    this.hideSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DetailActionButton(
            label: primaryLabel,
            styleKind: primaryStyle,
            onTap: onPrimaryTap,
          ),
        ),
        if (!hideSecondary) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _DetailActionButton(
              label: secondaryLabel,
              styleKind: secondaryStyle,
              onTap: onSecondaryTap ?? () {},
            ),
          ),
        ],
      ],
    );
  }
}

class _DetailActionButton extends StatelessWidget {
  final String label;
  final BookingActionStyle styleKind;
  final VoidCallback onTap;

  const _DetailActionButton({
    required this.label,
    required this.styleKind,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (styleKind == BookingActionStyle.primary) {
      return GradientButton(label: label, onPressed: onTap);
    }

    return SecondaryButton(label: label, onPressed: onTap);
  }
}
