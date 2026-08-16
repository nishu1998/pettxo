import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/service_duration.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/booking_v3_models.dart';
import '../../domain/models/canonical_booking_request_models.dart';
import 'canonical_booking_request_status_screen.dart';

class CanonicalBookingRequestReviewScreen extends StatefulWidget {
  final CanonicalBookingRequestInput input;
  final String serviceName;
  final String providerName;
  final String serviceImageUrl;
  final String timezone;
  final String schedulingMode;

  const CanonicalBookingRequestReviewScreen({
    super.key,
    required this.input,
    required this.serviceName,
    required this.providerName,
    required this.serviceImageUrl,
    required this.timezone,
    required this.schedulingMode,
  });

  @override
  State<CanonicalBookingRequestReviewScreen> createState() =>
      _CanonicalBookingRequestReviewScreenState();
}

class _CanonicalBookingRequestReviewScreenState
    extends State<CanonicalBookingRequestReviewScreen> {
  final BookingRepository _bookingRepository = BookingRepository();
  bool _isSubmitting = false;

  CanonicalSlotRequestInput get _slotRequest => widget.input.slotRequest!;

  String get _providerId {
    final slots = _slotRequest.selection.slots;
    return slots.isNotEmpty ? slots.first.providerId : '';
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (kDebugMode) {
      debugPrint(
        '[BookingScheduleVerify] start providerId=$_providerId serviceId=${widget.input.serviceId} selectedStart=${_slotRequest.selection.scheduledStartAt.toIso8601String()} selectedEnd=${_slotRequest.selection.scheduledEndAt.toIso8601String()} timezone=${widget.timezone}',
      );
      debugPrint(
        '[BookingCreateV3] start providerId=$_providerId serviceId=${widget.input.serviceId} selectedDays=${_slotRequest.selectedDays?.length ?? 0} slotCount=${_slotRequest.selection.slots.length}',
      );
    }
    setState(() => _isSubmitting = true);
    try {
      final result = await _bookingRepository.createBookingRequestV3(
        input: widget.input,
      );
      if (kDebugMode) {
        debugPrint(
          '[BookingCreateV3] success providerId=$_providerId serviceId=${widget.input.serviceId} bookingId=${result.bookingId}',
        );
      }
      if (!mounted) return;
      AppSnackbar.showSuccess(
        context,
        'Your request has been sent. Nothing has been charged.',
      );
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CanonicalBookingRequestStatusScreen(
            bookingId: result.bookingId,
            initialResult: result,
            serviceName: widget.serviceName,
            providerName: widget.providerName,
            serviceImageUrl: widget.serviceImageUrl,
            exitToBookingsOnClose: true,
          ),
        ),
      );
    } on CanonicalBookingRequestException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BookingCreateV3] failed providerId=$_providerId serviceId=${widget.input.serviceId} code=${error.code.name} safeMessage=${error.message} issues=${error.issues.join("|")}',
        );
      }
      if (!mounted) return;
      final isTimeout =
          error.message.toLowerCase().contains('deadline-exceeded') ||
          error.message.toLowerCase().contains('timeout');
      AppSnackbar.showError(
        context,
        isTimeout
            ? 'We could not confirm the request in time. Tap Send request again to safely retry.'
            : error.message,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[BookingCreateV3] failed providerId=$_providerId serviceId=${widget.input.serviceId} safeMessage=unexpected_error error=$error',
        );
      }
      if (!mounted) return;
      AppSnackbar.showError(
        context,
        'We could not send your request right now. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = _slotRequest.selection;
    final slots = selection.slots;
    final segments =
        selection.segments ?? const <SlotBookingScheduleSegmentV3>[];
    final estimatedSubtotal = _slotRequest.estimatedSubtotalPaise / 100;
    final visibleSegments = segments.isNotEmpty
        ? segments
        : <SlotBookingScheduleSegmentV3>[
            SlotBookingScheduleSegmentV3(
              serviceDateKey: slots.first.serviceDateKey ?? slots.first.dateKey,
              slotIds: slots.map((slot) => slot.slotId).toList(growable: false),
              startAt: selection.scheduledStartAt,
              endAt: selection.scheduledEndAt,
              durationMinutes: selection.totalDurationMinutes,
              schedulingMode: widget.schedulingMode,
            ),
          ];
    final serviceDayCount = selection.serviceDayCount ?? visibleSegments.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Review request',
          style: TextStyle(
            color: AppColors.textDark,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
          children: [
            _ReviewHeroCard(
              serviceName: widget.serviceName,
              providerName: widget.providerName,
              serviceImageUrl: widget.serviceImageUrl,
            ),
            const SizedBox(height: 16),
            const _NoticeCard(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Nothing will be charged now.',
              message:
                  'This request only asks the provider to review your selected schedule.',
            ),
            const SizedBox(height: 12),
            const _NoticeCard(
              icon: Icons.schedule_outlined,
              title: 'Your selection is not reserved until payment succeeds.',
              message:
                  'Availability will be confirmed later if the provider accepts and payment is completed.',
            ),
            const SizedBox(height: 16),
            _ReviewCard(
              title: 'Booking summary',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReviewLine(
                    label: 'Service days',
                    value:
                        '$serviceDayCount day${serviceDayCount == 1 ? '' : 's'}',
                  ),
                  ...visibleSegments.map<Widget>(
                    (segment) => _ReviewLine(
                      label: _formatDate(segment.startAt),
                      value:
                          '${_formatTime(segment.startAt)} - ${_formatTime(segment.endAt)}',
                    ),
                  ),
                  _ReviewLine(
                    label: 'Slots',
                    value:
                        '${slots.length} slot${slots.length == 1 ? '' : 's'}',
                  ),
                  _ReviewLine(
                    label: 'Total duration',
                    value: _formatDuration(
                      _slotRequest.selection.totalDurationMinutes,
                      schedulingMode: widget.schedulingMode,
                    ),
                  ),
                  _ReviewLine(
                    label: 'Provider timezone',
                    value: widget.timezone,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _ReviewCard(
              title: 'Request details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReviewLine(
                    label: 'Total service price',
                    value: '₹${estimatedSubtotal.toStringAsFixed(0)}',
                  ),
                  const _ReviewLine(
                    label: 'Provider response',
                    value: 'The provider gets 60 minutes to respond.',
                  ),
                  const _ReviewLine(
                    label: 'Before payment',
                    value:
                        'Nothing is charged and no chat or contact details unlock.',
                  ),
                  const _ReviewLine(
                    label: 'Outside working hours',
                    value:
                        'If the provider is currently outside working hours, their response timer will start when working hours begin.',
                  ),
                  const _ReviewLine(
                    label: 'Pet details',
                    value:
                        'Your Pettxo profile details will stay attached to this request without exposing private contact information.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: 'Send request',
              onPressed: _isSubmitting ? null : _submit,
              isLoading: _isSubmitting,
            ),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Back',
              onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewHeroCard extends StatelessWidget {
  final String serviceName;
  final String providerName;
  final String serviceImageUrl;

  const _ReviewHeroCard({
    required this.serviceName,
    required this.providerName,
    required this.serviceImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 62,
              height: 62,
              child: serviceImageUrl.trim().isEmpty
                  ? Container(
                      color: const Color(0xFFFFEFE7),
                      child: const Icon(
                        Icons.pets_rounded,
                        color: AppColors.primary,
                      ),
                    )
                  : Image.network(
                      serviceImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFFFFEFE7),
                        child: const Icon(
                          Icons.pets_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceName,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  providerName.trim().isEmpty
                      ? 'Service provider'
                      : providerName,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ReviewCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  final String label;
  final String value;

  const _ReviewLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _NoticeCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4EE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _formatTime(DateTime date) {
  final hour = date.hour;
  final minute = date.minute;
  final suffix = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
}

String _formatDuration(int minutes, {String? schedulingMode}) {
  return formatServiceDurationLabel(
    durationMinutes: minutes,
    schedulingMode: schedulingMode,
  );
}
