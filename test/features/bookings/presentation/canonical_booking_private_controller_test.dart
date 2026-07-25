import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_private.dart';
import 'package:pettexo/features/bookings/presentation/controllers/canonical_booking_private_controller.dart';

void main() {
  Future<void> flushAsync() => Future<void>.delayed(Duration.zero);

  CanonicalBookingPrivateData privateData({
    required String bookingId,
    String parentOtpCode = '482913',
  }) {
    return CanonicalBookingPrivateData(
      bookingId: bookingId,
      parentId: 'parent-1',
      providerId: 'provider-1',
      parentOtpCode: parentOtpCode,
      otpState: 'ACTIVE',
      failedAttemptCount: 0,
      lockedUntil: null,
      verifiedAt: null,
      contactUnlockedAt: DateTime.utc(2026, 7, 22, 10, 30),
      createdAt: DateTime.utc(2026, 7, 22, 10, 30),
      updatedAt: DateTime.utc(2026, 7, 22, 10, 30),
    );
  }

  group('CanonicalBookingPrivateController', () {
    test(
      'bookingPrivate loads only when booking access is confirmed',
      () async {
        final streamController =
            StreamController<CanonicalBookingPrivateData?>.broadcast();
        var loadCount = 0;
        final controller = CanonicalBookingPrivateController(
          privateLoader: (bookingId) {
            loadCount += 1;
            return streamController.stream;
          },
        );

        controller.bind(bookingId: 'booking-1', shouldLoadPrivate: false);
        expect(loadCount, 0);
        expect(controller.state.hasData, isFalse);

        controller.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
        expect(loadCount, 1);
        expect(controller.state.isLoading, isTrue);

        await streamController.close();
        controller.dispose();
      },
    );

    test(
      'booking A private data is cleared before booking B is displayed',
      () async {
        final streams =
            <String, StreamController<CanonicalBookingPrivateData?>>{
              'booking-a':
                  StreamController<CanonicalBookingPrivateData?>.broadcast(),
              'booking-b':
                  StreamController<CanonicalBookingPrivateData?>.broadcast(),
            };
        final controller = CanonicalBookingPrivateController(
          privateLoader: (bookingId) => streams[bookingId]!.stream,
        );

        controller.bind(bookingId: 'booking-a', shouldLoadPrivate: true);
        streams['booking-a']!.add(privateData(bookingId: 'booking-a'));
        await flushAsync();

        expect(controller.state.privateData?.bookingId, 'booking-a');

        controller.bind(bookingId: 'booking-b', shouldLoadPrivate: true);
        expect(controller.state.bookingId, 'booking-b');
        expect(controller.state.privateData, isNull);
        expect(controller.state.isLoading, isTrue);

        await Future.wait(
          streams.values.map((controller) => controller.close()),
        );
        controller.dispose();
      },
    );

    test('logout clears private data', () async {
      final privateStream =
          StreamController<CanonicalBookingPrivateData?>.broadcast();
      final authStream = StreamController<Object?>.broadcast();
      final controller = CanonicalBookingPrivateController(
        privateLoader: (_) => privateStream.stream,
        authStateStreamFactory: () => authStream.stream,
      );

      controller.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
      privateStream.add(privateData(bookingId: 'booking-1'));
      await flushAsync();
      expect(controller.state.privateData?.bookingId, 'booking-1');

      authStream.add(null);
      await flushAsync();

      expect(controller.state.bookingId, '');
      expect(controller.state.privateData, isNull);
      expect(controller.state.errorMessage, isNull);

      await privateStream.close();
      await authStream.close();
      controller.dispose();
    });

    test(
      'PAYMENT_EXPIRED never displays cached confirmed private data',
      () async {
        final privateStream =
            StreamController<CanonicalBookingPrivateData?>.broadcast();
        final controller = CanonicalBookingPrivateController(
          privateLoader: (_) => privateStream.stream,
        );

        controller.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
        privateStream.add(privateData(bookingId: 'booking-1'));
        await flushAsync();

        controller.bind(bookingId: 'booking-1', shouldLoadPrivate: false);
        expect(controller.state.privateData, isNull);
        expect(controller.state.isLoading, isFalse);

        await privateStream.close();
        controller.dispose();
      },
    );

    test(
      'REFUND_PENDING-style blocked access never displays cached confirmed private data',
      () async {
        final privateStream =
            StreamController<CanonicalBookingPrivateData?>.broadcast();
        final controller = CanonicalBookingPrivateController(
          privateLoader: (_) => privateStream.stream,
        );

        controller.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
        privateStream.add(privateData(bookingId: 'booking-1'));
        await flushAsync();

        controller.bind(bookingId: 'booking-1', shouldLoadPrivate: false);
        expect(controller.state.privateData, isNull);

        await privateStream.close();
        controller.dispose();
      },
    );

    test(
      'pre-confirmation states never display OTP or private details',
      () async {
        const blockedStates = <String>[
          'CAPTURE_REPORTED',
          'CONFIRMING',
          'CAPTURED_REQUIRES_RECONCILIATION',
          'REQUESTED',
          'PENDING_PROVIDER',
          'ACCEPTED_AWAITING_PAYMENT',
          'FAILED',
          'EXPIRED',
          'REFUNDED',
        ];
        final privateStream =
            StreamController<CanonicalBookingPrivateData?>.broadcast();
        final controller = CanonicalBookingPrivateController(
          privateLoader: (_) => privateStream.stream,
        );

        for (final state in blockedStates) {
          controller.bind(
            bookingId: 'booking-$state',
            shouldLoadPrivate: false,
          );
          expect(controller.state.privateData, isNull, reason: state);
          expect(controller.state.errorMessage, isNull, reason: state);
        }

        await privateStream.close();
        controller.dispose();
      },
    );

    test('malformed private document errors show a safe error', () async {
      final privateStream =
          StreamController<CanonicalBookingPrivateData?>.broadcast();
      final controller = CanonicalBookingPrivateController(
        privateLoader: (_) => privateStream.stream,
      );

      controller.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
      privateStream.addError(
        FormatException(
          'OTP 482913 for +919999999999 at Andheri West, Mumbai was malformed',
        ),
      );
      await flushAsync();

      expect(
        controller.state.errorMessage,
        'Paid-only booking details could not be loaded right now.',
      );
      expect(controller.state.privateData, isNull);

      await privateStream.close();
      controller.dispose();
    });

    test('error text excludes OTP, phone, address, and coordinates', () async {
      final privateStream =
          StreamController<CanonicalBookingPrivateData?>.broadcast();
      final controller = CanonicalBookingPrivateController(
        privateLoader: (_) => privateStream.stream,
      );

      controller.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
      privateStream.addError(
        StateError(
          'otp=482913 phone=+919999999999 address=Andheri West, Mumbai lat=19.136 long=72.829',
        ),
      );
      await flushAsync();

      final errorMessage = controller.state.errorMessage ?? '';
      expect(errorMessage.contains('482913'), isFalse);
      expect(errorMessage.contains('+919999999999'), isFalse);
      expect(errorMessage.contains('Andheri West'), isFalse);
      expect(errorMessage.contains('19.136'), isFalse);
      expect(errorMessage.contains('72.829'), isFalse);

      await privateStream.close();
      controller.dispose();
    });

    test(
      'route arguments do not carry private model data into the controller',
      () async {
        final privateStream =
            StreamController<CanonicalBookingPrivateData?>.broadcast();
        final controller = CanonicalBookingPrivateController(
          privateLoader: (_) => privateStream.stream,
        );

        controller.bind(
          bookingId: 'booking-route-only',
          shouldLoadPrivate: true,
        );
        expect(controller.state.bookingId, 'booking-route-only');
        expect(controller.state.privateData, isNull);

        await privateStream.close();
        controller.dispose();
      },
    );

    test(
      'app restart refetches bookingPrivate from the repository seam',
      () async {
        var loadCount = 0;
        final firstStream =
            StreamController<CanonicalBookingPrivateData?>.broadcast();
        final secondStream =
            StreamController<CanonicalBookingPrivateData?>.broadcast();
        final queuedStreams = <StreamController<CanonicalBookingPrivateData?>>[
          firstStream,
          secondStream,
        ];

        Stream<CanonicalBookingPrivateData?> loader(String _) {
          final stream = queuedStreams[loadCount];
          loadCount += 1;
          return stream.stream;
        }

        final firstController = CanonicalBookingPrivateController(
          privateLoader: loader,
        );
        firstController.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
        firstStream.add(privateData(bookingId: 'booking-1'));
        await flushAsync();
        expect(firstController.state.privateData?.bookingId, 'booking-1');
        firstController.dispose();

        final secondController = CanonicalBookingPrivateController(
          privateLoader: loader,
        );
        secondController.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
        secondStream.add(privateData(bookingId: 'booking-1'));
        await flushAsync();

        expect(loadCount, 2);
        expect(secondController.state.privateData?.bookingId, 'booking-1');

        await firstStream.close();
        await secondStream.close();
        secondController.dispose();
      },
    );

    test('terminal unconfirmed state clears stale private data', () async {
      final privateStream =
          StreamController<CanonicalBookingPrivateData?>.broadcast();
      final controller = CanonicalBookingPrivateController(
        privateLoader: (_) => privateStream.stream,
      );

      controller.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
      privateStream.add(privateData(bookingId: 'booking-1'));
      await flushAsync();
      expect(controller.state.hasData, isTrue);

      controller.bind(bookingId: 'booking-1', shouldLoadPrivate: false);
      expect(controller.state.hasData, isFalse);

      await privateStream.close();
      controller.dispose();
    });

    test(
      'switching actor does not reuse another actor private state',
      () async {
        final privateStreamA =
            StreamController<CanonicalBookingPrivateData?>.broadcast();
        final privateStreamB =
            StreamController<CanonicalBookingPrivateData?>.broadcast();
        final authStream = StreamController<Object?>.broadcast();
        var loadCount = 0;
        final controller = CanonicalBookingPrivateController(
          privateLoader: (_) {
            loadCount += 1;
            return loadCount == 1
                ? privateStreamA.stream
                : privateStreamB.stream;
          },
          authStateStreamFactory: () => authStream.stream,
        );

        controller.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
        privateStreamA.add(privateData(bookingId: 'booking-1'));
        await flushAsync();
        expect(controller.state.privateData?.bookingId, 'booking-1');

        authStream.add(null);
        await flushAsync();
        expect(controller.state.privateData, isNull);

        controller.bind(bookingId: 'booking-1', shouldLoadPrivate: true);
        privateStreamB.add(
          privateData(bookingId: 'booking-1', parentOtpCode: '123456'),
        );
        await flushAsync();

        expect(controller.state.privateData?.parentOtpCode, '123456');
        expect(controller.state.privateData?.otpState, 'ACTIVE');

        await privateStreamA.close();
        await privateStreamB.close();
        await authStream.close();
        controller.dispose();
      },
    );
  });
}
