import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../support/presentation/screens/help_support_screen.dart';
import '../../moderation/presentation/widgets/report_sheet.dart';
import '../data/blocked_relationship_repository.dart';

const String blockingDisabledMessage =
    "Blocking isn't available yet. If you feel unsafe, you can report this user and our team will review it.";

String blockingFailureMessage(BlockingFailureKind kind) {
  switch (kind) {
    case BlockingFailureKind.unauthenticated:
      return 'Please sign in and try again.';
    case BlockingFailureKind.invalidTarget:
      return 'This user cannot be updated right now.';
    case BlockingFailureKind.protectedBooking:
      return "Blocking is unavailable during an active paid booking or unresolved dispute.";
    case BlockingFailureKind.paymentReconciliation:
      return 'Blocking is temporarily unavailable because a booking payment needs verification. Contact Pettxo Support.';
    case BlockingFailureKind.supportRequired:
      return 'Pettxo Support needs to review this relationship before blocking can continue.';
    case BlockingFailureKind.blockingDisabled:
      return blockingDisabledMessage;
    case BlockingFailureKind.notFound:
      return 'This user is no longer available.';
    case BlockingFailureKind.permissionDenied:
      return 'You do not have permission to update this relationship.';
    case BlockingFailureKind.unavailable:
    case BlockingFailureKind.timeout:
      return 'Check your connection and try again.';
    case BlockingFailureKind.unexpected:
      return 'We could not update this relationship right now.';
  }
}

Future<bool> showBlockConfirmation(
  BuildContext context,
  UserRelationshipState state,
) async {
  final cancelsUnpaid = state.acceptedUnpaidBookingCount > 0;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            cancelsUnpaid
                ? 'Block user and cancel unpaid bookings?'
                : 'Block this user?',
          ),
          content: Text(
            cancelsUnpaid
                ? "Blocking this user will cancel your accepted bookings that haven't been paid for. You won't be able to complete payment for those bookings."
                : "You and this user won't be able to message, follow, or interact with each other on Pettxo. Their posts and services will also be hidden from your normal experience.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(cancelsUnpaid ? 'Keep Bookings' : 'Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE15656),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(cancelsUnpaid ? 'Block and Cancel' : 'Block User'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> showUnblockConfirmation(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unblock this user?'),
          content: const Text(
            "This removes only your block. Previous follows and conversations won't be restored automatically, and restrictions remain if the other user has blocked you.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Unblock User'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> showBlockingUnavailable(
  BuildContext context, {
  required String reasonCode,
  required String reportTargetUid,
}) async {
  final reconciliation =
      reasonCode.trim().toUpperCase() == 'PAYMENT_RECONCILIATION_REQUIRED' ||
      reasonCode.trim().toUpperCase() == 'INVALID_CANONICAL_BOOKING';
  final supportRequired =
      reasonCode.trim().toUpperCase() == 'PAIR_BOOKING_LIMIT_EXCEEDED';
  final disabled = isBlockingDisabledReason(reasonCode);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Blocking temporarily unavailable'),
      content: Text(
        disabled
            ? blockingDisabledMessage
            : reconciliation
            ? 'A booking payment needs verification before blocking can continue. Contact Pettxo Support.'
            : supportRequired
            ? 'Pettxo Support needs to review your booking history before blocking can continue.'
            : "You can't block this user while you have an active paid booking or an open dispute. You can still report them or contact support.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('OK'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            showUserReport(context, targetUid: reportTargetUid);
          },
          child: const Text('Report User'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HelpSupportScreen()),
            );
          },
          child: const Text('Contact Support'),
        ),
      ],
    ),
  );
}

Future<void> showUserReport(
  BuildContext context, {
  required String targetUid,
}) async {
  await ReportSheet.show(context: context, type: 'user', targetId: targetUid);
}
