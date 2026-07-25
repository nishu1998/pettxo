import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'booking v3.2 cutover audit blocks deleted booking symbols from returning',
    () {
      final repoRoot = Directory.current;
      final files = <File>[
        ..._collectFiles(repoRoot.uri.resolve('lib/')),
        ..._collectFiles(repoRoot.uri.resolve('functions/src/')),
        ..._collectFiles(repoRoot.uri.resolve('functions/test/')),
        File.fromUri(repoRoot.uri.resolve('firestore.rules')),
        File.fromUri(repoRoot.uri.resolve('firestore.indexes.json')),
      ].where((file) => file.existsSync()).toList(growable: false);

      const bannedTokens = <String, String>{
        'PaymentReviewScreen': 'old payment review screen should stay deleted',
        'createRazorpayBookingOrder':
            'legacy booking payment callable must stay removed',
        'getPendingPaymentBooking':
            'legacy pending-payment lookup must stay removed',
        'deletePendingPaymentBookingForCustomer':
            'legacy pending-payment deletion must stay removed',
        'markRazorpayPaymentFailed':
            'legacy payment failure callable must stay removed',
        'acceptBookingRequest(':
            'legacy provider accept callable must stay removed',
        'rejectBookingRequest(':
            'legacy provider reject callable must stay removed',
        'previewCancellation(':
            'legacy cancellation preview callable must stay removed',
        'raiseDispute(': 'legacy dispute callable must stay removed',
        'verifyBookingOtpAndStart':
            'legacy OTP start callable must stay removed',
        'resolveBookingFlowV3': 'rollout resolver callable must stay removed',
        'bookingRollout': 'rollout source should stay deleted',
        'legacyBookingStatus':
            'legacy booking status adapter should stay deleted',
        'handleLegacyWebhook':
            'legacy payment webhook fallback must stay removed',
        'IGNORED_LEGACY': 'legacy webhook routing result must stay removed',
        'bookingUpdate': 'old booking push payload type should stay removed',
        "'booking_detail_screen.dart'":
            'deleted legacy booking detail screen import should stay removed',
        "'payment_review_screen.dart'":
            'deleted legacy payment review import should stay removed',
        "'booking_card.dart'":
            'deleted legacy booking card import should stay removed',
        "'booking_model.dart'":
            'deleted legacy booking model import should stay removed',
        "'pending_payment_booking.dart'":
            'deleted legacy pending payment model import should stay removed',
        "'booking_cancellation_preview.dart'":
            'deleted legacy cancellation preview model import should stay removed',
      };

      final violations = <String>[];
      for (final file in files) {
        final relativePath = _relativePath(repoRoot.path, file.path);
        final contents = file.readAsStringSync();
        bannedTokens.forEach((token, reason) {
          if (contents.contains(token)) {
            violations.add('$relativePath -> $token ($reason)');
          }
        });
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
}

List<File> _collectFiles(Uri directoryUri) {
  final directory = Directory.fromUri(directoryUri);
  if (!directory.existsSync()) return const <File>[];

  return directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) {
        final path = file.path;
        return path.endsWith('.dart') ||
            path.endsWith('.ts') ||
            path.endsWith('.js');
      })
      .toList(growable: false);
}

String _relativePath(String rootPath, String filePath) {
  if (filePath.startsWith(rootPath)) {
    return filePath.substring(rootPath.length + 1);
  }
  return filePath;
}
