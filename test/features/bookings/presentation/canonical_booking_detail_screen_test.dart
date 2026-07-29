import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/widgets/app_buttons.dart';
import 'package:pettexo/features/bookings/data/repositories/booking_repository.dart';
import 'package:pettexo/features/bookings/domain/models/booking_document_v3.dart';
import 'package:pettexo/features/bookings/domain/models/booking_read_model.dart';
import 'package:pettexo/features/bookings/domain/models/booking_v3_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_cancellation_models.dart';
import 'package:pettexo/features/bookings/domain/models/canonical_booking_private.dart';
import 'package:pettexo/features/bookings/presentation/controllers/canonical_booking_private_controller.dart';
import 'package:pettexo/features/bookings/presentation/screens/canonical_booking_detail_screen.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  group('CanonicalBookingDetailScreen', () {
    late _FakeBookingRepository bookingRepository;

    setUp(() {
      bookingRepository = _FakeBookingRepository();
      bookingRepository.booking = _buildConfirmedBooking();
    });

    testWidgets(
      'shows OTP and opens canonical chat, dialer, and maps actions safely',
      (tester) async {
        final openedChatBookingIds = <String>[];
        final launchedUris = <Uri>[];
        final launchModes = <LaunchMode?>[];

        bookingRepository.participantPrivateData =
            _buildPrivateParticipantsData();
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
          onOpenChatOverride: (bookingId) async {
            openedChatBookingIds.add(bookingId);
          },
          canLaunchUrlOverride: (_) async => true,
          launchUrlOverride: (uri, {mode = LaunchMode.platformDefault}) async {
            launchedUris.add(uri);
            launchModes.add(mode);
            return true;
          },
        );

        expect(find.text('Booking Details'), findsOneWidget);
        expect(find.text('Daily Dog Walk'), findsWidgets);
        expect(find.text('Prakash Gautam'), findsWidgets);
        expect(find.text('BOOKING SUMMARY'), findsOneWidget);
        expect(find.text('BOOKING STATUS'), findsOneWidget);
        expect(find.text('SLOT'), findsNothing);
        await _scrollUntilTextVisible(tester, 'SERVICE-START OTP');
        await _pumpUntilTextExists(tester, 'START OTP');

        expect(find.text('START OTP'), findsOneWidget);
        expect(
          find.text(
            'Bookings made outside Pettxo are not covered by OTP verification, dispute protection, or refunds.',
          ),
          findsNothing,
        );
        expect(
          find.text(
            'Share this with Prakash Gautam only when the service actually begins. The OTP is what starts the clock.',
          ),
          findsOneWidget,
        );

        await _scrollUntilTextVisible(tester, 'SERVICE LOCATION');
        await tester.ensureVisible(find.text('Call provider'));
        await tester.pump();
        expect(find.text('Call provider'), findsOneWidget);

        await tester.tap(find.text('Call provider'));
        await tester.pump();
        expect(launchedUris.first.scheme, 'tel');
        expect(launchedUris.first.path, '9876543210');

        await tester.ensureVisible(find.text('Get directions'));
        await tester.pump();
        expect(find.text('Get directions'), findsOneWidget);
        await tester.tap(find.text('Get directions'));
        await tester.pump();
        expect(
          launchedUris.last.toString(),
          contains('query=12.9716%2C77.5946'),
        );
        expect(launchModes.last, LaunchMode.externalApplication);

        await _scrollUntilTextVisible(tester, 'BOOKING CHAT');
        await tester.ensureVisible(find.text('Message provider'));
        await tester.pump();
        expect(find.text('Message provider'), findsOneWidget);
        expect(
          find.text('Coordinate service details directly with the provider.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Message provider'));
        await tester.pump();
        expect(openedChatBookingIds, ['booking-1']);
      },
    );

    testWidgets(
      'renders slot schedules with explicit date, time, and duration',
      (tester) async {
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        expect(find.text('BOOKING SUMMARY'), findsOneWidget);
        expect(find.text('28 Jul 2026'), findsOneWidget);
        expect(find.text('9:00 AM to 10:00 AM'), findsOneWidget);
        expect(find.text('60 min'), findsOneWidget);
      },
    );

    testWidgets(
      'renders continuous multi-slot bookings as one combined window',
      (tester) async {
        bookingRepository.booking = _buildMultiSlotConfirmedBooking();
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        expect(find.text('28 Jul 2026'), findsOneWidget);
        expect(find.text('9:00 AM to 11:00 AM'), findsOneWidget);
        expect(find.text('120 min'), findsOneWidget);
      },
    );

    testWidgets('renders range booking schedule rows for both booking roles', (
      tester,
    ) async {
      bookingRepository.booking = _buildRangeConfirmedBooking();
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
        currentUserIdOverride: 'provider-1',
      );

      expect(find.text('Stay booking'), findsOneWidget);
      expect(find.text('Check-in'), findsOneWidget);
      expect(find.text('29 Jul 2026 3:30 PM'), findsOneWidget);
      expect(find.text('Check-out'), findsOneWidget);
      expect(find.text('31 Jul 2026 11:30 AM'), findsOneWidget);
      expect(find.text('2 nights'), findsOneWidget);
    });

    testWidgets('falls back safely when schedule bounds are malformed', (
      tester,
    ) async {
      bookingRepository.booking = _buildMalformedSlotConfirmedBooking();
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
      );

      expect(find.text('Daily Dog Walk'), findsWidgets);
      expect(find.text('Pending'), findsWidgets);
    });

    testWidgets('reuses the existing OTP stream across rebuilds', (
      tester,
    ) async {
      var privateLoadCount = 0;
      bookingRepository.participantPrivateData =
          _buildPrivateParticipantsData();
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) {
          privateLoadCount += 1;
          return Stream.value(_buildPrivateOtpData());
        },
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
      );

      await _scrollUntilTextVisible(tester, 'SERVICE-START OTP');
      await _pumpUntilTextExists(tester, 'START OTP');
      expect(find.text('START OTP'), findsOneWidget);
      expect(privateLoadCount, 1);

      await tester.pump();
      await tester.pump();

      await _scrollUntilTextVisible(tester, 'SERVICE-START OTP');
      await _pumpUntilTextExists(tester, 'START OTP');
      expect(find.text('START OTP'), findsOneWidget);
      expect(privateLoadCount, 1);
    });

    testWidgets('shows retry state when private OTP data fails temporarily', (
      tester,
    ) async {
      var privateLoadCount = 0;
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) {
          privateLoadCount += 1;
          if (privateLoadCount == 1) {
            return Stream<CanonicalBookingPrivateData?>.error(
              StateError('temporary'),
            );
          }
          return Stream.value(_buildPrivateOtpData());
        },
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
      );
      await tester.pump();

      await _scrollUntilTextVisible(tester, 'SERVICE-START OTP');
      await tester.ensureVisible(find.text('Retry details'));
      await tester.pump();
      expect(find.text('Retry details'), findsOneWidget);
      expect(
        find.text('Your service OTP could not be loaded right now.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry details'));
      await tester.pump();
      await tester.pump();

      expect(privateLoadCount, 2);
      await _scrollUntilTextVisible(tester, 'SERVICE-START OTP');
      await tester.ensureVisible(find.text('START OTP'));
      await tester.pump();
      expect(find.text('START OTP'), findsOneWidget);
    });

    testWidgets('hides provider call action when no private phone exists', (
      tester,
    ) async {
      bookingRepository.participantPrivateData = _buildPrivateParticipantsData(
        providerPhoneNumber: '',
      );
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
      );

      await _scrollUntilTextVisible(tester, 'SERVICE LOCATION');
      expect(find.text('Call provider'), findsNothing);
      expect(find.text('Get directions'), findsOneWidget);
    });

    testWidgets('falls back to address when coordinates are unavailable', (
      tester,
    ) async {
      final launchedUris = <Uri>[];
      bookingRepository.participantPrivateData = _buildPrivateParticipantsData(
        latitude: null,
        longitude: null,
      );
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
        canLaunchUrlOverride: (_) async => true,
        launchUrlOverride: (uri, {mode = LaunchMode.platformDefault}) async {
          launchedUris.add(uri);
          return true;
        },
      );

      await _scrollUntilTextVisible(tester, 'SERVICE LOCATION');
      await tester.ensureVisible(find.text('Get directions'));
      await tester.pump();
      await tester.tap(find.text('Get directions'));
      await tester.pump();

      expect(
        launchedUris.single.toString(),
        contains('query=221B%20Baker%20Street%2C%20Bengaluru%2C%20Karnataka'),
      );
    });

    testWidgets('hides map action when no canonical location is available', (
      tester,
    ) async {
      bookingRepository.participantPrivateData = _buildPrivateParticipantsData(
        exactAddress: '',
        latitude: null,
        longitude: null,
      );
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
      );

      await _scrollUntilTextVisible(tester, 'BOOKING CHAT');
      expect(find.text('Get directions'), findsNothing);
    });

    testWidgets(
      'participant-private failure does not hide summary, OTP, or chat action',
      (tester) async {
        bookingRepository.participantPrivateStream =
            Stream<CanonicalBookingPrivateParticipantsData?>.error(
              StateError('participant-private-temporary'),
            );
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );
        await tester.pump();

        expect(find.text('Daily Dog Walk'), findsWidgets);
        expect(find.text('BOOKING STATUS'), findsOneWidget);

        await _scrollUntilTextVisible(tester, 'SERVICE-START OTP');
        await tester.ensureVisible(find.text('START OTP'));
        await tester.pump();
        expect(find.text('START OTP'), findsOneWidget);
        await _scrollUntilTextVisible(tester, 'BOOKING CHAT');
        await tester.ensureVisible(find.text('Message provider'));
        await tester.pump();
        expect(find.text('Message provider'), findsOneWidget);
      },
    );

    testWidgets('customer never sees provider start controls', (tester) async {
      bookingRepository.participantPrivateData =
          _buildPrivateParticipantsData();
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
        currentUserIdOverride: 'parent-1',
      );

      expect(find.text('Start service'), findsNothing);
      expect(find.text('Verify OTP'), findsNothing);
      expect(find.text('Complete service'), findsNothing);
    });

    testWidgets('in-progress customer shows service started instead of OTP', (
      tester,
    ) async {
      bookingRepository.booking = _buildInProgressBooking();
      bookingRepository.participantPrivateData =
          _buildPrivateParticipantsData();
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) =>
            Stream.value(_buildPrivateOtpData(otpState: 'USED')),
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
      );

      await _scrollUntilTextVisible(
        tester,
        'Service started. Your booking OTP has already been used for this booking.',
      );
      expect(
        find.text(
          'Service started. Your booking OTP has already been used for this booking.',
        ),
        findsOneWidget,
      );
      expect(find.text('654321'), findsNothing);
    });

    testWidgets('provider sees OTP entry action without customer OTP content', (
      tester,
    ) async {
      bookingRepository.participantPrivateData =
          _buildPrivateParticipantsData();
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
        currentUserIdOverride: 'provider-1',
      );

      await _scrollToProviderStartSection(tester);
      await tester.ensureVisible(find.text('Message customer'));
      await tester.pump();
      expect(find.text('Message customer'), findsOneWidget);
      expect(
        find.text('Use this chat to coordinate details for this booking.'),
        findsOneWidget,
      );
      expect(find.text('Enter customer OTP'), findsOneWidget);
      expect(find.text('Start service'), findsNothing);
      expect(find.text('Service OTP'), findsNothing);
      expect(find.text('654321'), findsNothing);
      expect(find.text('Reveal OTP'), findsNothing);
    });

    testWidgets(
      'provider OTP submit stays disabled until six digits are entered',
      (tester) async {
        bookingRepository.participantPrivateData =
            _buildPrivateParticipantsData();
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
          currentUserIdOverride: 'provider-1',
        );

        await _scrollToProviderStartSection(tester);
        await tester.tap(find.text('Enter customer OTP'));
        await tester.pumpAndSettle();

        var verifyButton = tester.widget<GradientButton>(
          find.widgetWithText(GradientButton, 'Verify OTP'),
        );
        expect(verifyButton.onPressed, isNull);

        await tester.enterText(find.byType(TextField), '12a 34');
        await tester.pump();
        verifyButton = tester.widget<GradientButton>(
          find.widgetWithText(GradientButton, 'Verify OTP'),
        );
        expect(verifyButton.onPressed, isNull);

        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump();
        verifyButton = tester.widget<GradientButton>(
          find.widgetWithText(GradientButton, 'Verify OTP'),
        );
        expect(verifyButton.onPressed, isNotNull);
      },
    );

    testWidgets(
      'duplicate provider submit is prevented and request attempt id is sent once',
      (tester) async {
        bookingRepository.participantPrivateData =
            _buildPrivateParticipantsData();
        bookingRepository.bookingStreamController =
            StreamController<BookingReadModel?>.broadcast();
        bookingRepository.emitBooking(_buildConfirmedBooking());
        bookingRepository.verifyBookingStartOtpCompleter = Completer<void>();
        bookingRepository.onVerifyBookingStartOtp = () async {
          bookingRepository.booking = _buildInProgressBooking();
          bookingRepository.emitBooking(_buildInProgressBooking());
        };
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
          currentUserIdOverride: 'provider-1',
        );

        await _scrollToProviderStartSection(tester);
        await tester.tap(find.text('Enter customer OTP'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump();

        await tester.tap(find.text('Verify OTP'));
        await tester.pump();
        final loadingVerifyButton = tester
            .widgetList<GradientButton>(find.byType(GradientButton))
            .where((widget) => widget.label == 'Verifying...')
            .first;
        expect(loadingVerifyButton.isLoading, isTrue);
        expect(loadingVerifyButton.onPressed, isNull);

        expect(bookingRepository.verifyBookingStartOtpCallCount, 1);
        expect(bookingRepository.lastVerifyBookingId, 'booking-1');
        expect(bookingRepository.lastVerifyOtp, '123456');
        expect(bookingRepository.lastVerifyRequestAttemptId, isNotEmpty);

        bookingRepository.verifyBookingStartOtpCompleter!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'successful provider verification reacts to in-progress and hides OTP action',
      (tester) async {
        bookingRepository.participantPrivateData =
            _buildPrivateParticipantsData();
        bookingRepository.bookingStreamController =
            StreamController<BookingReadModel?>.broadcast();
        bookingRepository.emitBooking(_buildConfirmedBooking());
        bookingRepository.onVerifyBookingStartOtp = () async {
          bookingRepository.booking = _buildInProgressBooking();
          bookingRepository.emitBooking(_buildInProgressBooking());
        };
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
          currentUserIdOverride: 'provider-1',
        );

        await _scrollToProviderStartSection(tester);
        await tester.tap(find.text('Enter customer OTP'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump();
        await tester.tap(find.text('Verify OTP'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Enter customer OTP'), findsNothing);
        expect(find.text('Complete service'), findsOneWidget);
        expect(
          bookingRepository.booking?.state,
          CanonicalBookingStateV3.inProgress,
        );
      },
    );

    testWidgets(
      'provider sees safe OTP error text instead of raw backend codes',
      (tester) async {
        bookingRepository.participantPrivateData =
            _buildPrivateParticipantsData();
        bookingRepository.verifyBookingStartOtpError =
            FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'The OTP is invalid.',
              details: 'INVALID_OTP',
            );
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
          currentUserIdOverride: 'provider-1',
        );

        await _scrollToProviderStartSection(tester);
        await tester.tap(find.text('Enter customer OTP'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '123456');
        await tester.pump();
        await tester.tap(find.text('Verify OTP'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(
          find.text(
            'The OTP is incorrect. Ask the customer to confirm the code and try again.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('permission-denied'), findsNothing);
        expect(find.textContaining('INVALID_OTP'), findsNothing);
      },
    );
  });
}

Future<void> _scrollUntilTextVisible(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pump();
    return;
  }
  for (var i = 0; i < 20 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -220));
    await tester.pump();
  }
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
    await tester.pump();
  }
}

Future<void> _pumpUntilTextExists(WidgetTester tester, String text) async {
  for (var i = 0; i < 10 && find.text(text).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _scrollToProviderStartSection(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -1200));
  await tester.pump();
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeBookingRepository bookingRepository,
  required CanonicalBookingPrivateController privateController,
  String currentUserIdOverride = 'parent-1',
  Future<void> Function(String bookingId)? onOpenChatOverride,
  Future<bool> Function(Uri uri)? canLaunchUrlOverride,
  Future<bool> Function(Uri uri, {LaunchMode mode})? launchUrlOverride,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CanonicalBookingDetailScreen(
        bookingId: 'booking-1',
        repository: bookingRepository,
        privateController: privateController,
        currentUserIdOverride: currentUserIdOverride,
        onOpenChatOverride: onOpenChatOverride,
        canLaunchUrlOverride: canLaunchUrlOverride,
        launchUrlOverride: launchUrlOverride,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

class _FakeBookingRepository extends BookingRepository {
  CanonicalBookingDocumentV3? booking;
  CanonicalBookingPrivateParticipantsData? participantPrivateData;
  Stream<CanonicalBookingPrivateParticipantsData?>? participantPrivateStream;
  StreamController<BookingReadModel?>? bookingStreamController;
  Completer<void>? verifyBookingStartOtpCompleter;
  Future<void> Function()? onVerifyBookingStartOtp;
  Object? verifyBookingStartOtpError;
  int verifyBookingStartOtpCallCount = 0;
  String lastVerifyBookingId = '';
  String lastVerifyOtp = '';
  String lastVerifyRequestAttemptId = '';

  @override
  Stream<BookingReadModel?> watchCanonicalBooking(String bookingId) async* {
    yield booking == null
        ? null
        : CanonicalBookingReadModel(
            documentId: booking!.bookingIdForTest,
            booking: booking!,
          );
    if (bookingStreamController != null) {
      yield* bookingStreamController!.stream;
    }
  }

  @override
  Stream<CanonicalBookingPrivateParticipantsData?>
  watchCanonicalBookingPrivateParticipants(String bookingId) =>
      participantPrivateStream ?? Stream.value(participantPrivateData);

  @override
  Stream<CanonicalBookingCancellationRecord?> watchCanonicalBookingCancellation(
    String bookingId,
  ) => Stream.value(null);

  @override
  Future<BookingReadModel?> fetchCanonicalBooking(String bookingId) async {
    if (booking == null) return null;
    return CanonicalBookingReadModel(
      documentId: booking!.bookingIdForTest,
      booking: booking!,
    );
  }

  @override
  Future<void> verifyBookingStartOtpV3({
    required String bookingId,
    required String otp,
    required String requestAttemptId,
  }) async {
    verifyBookingStartOtpCallCount += 1;
    lastVerifyBookingId = bookingId;
    lastVerifyOtp = otp;
    lastVerifyRequestAttemptId = requestAttemptId;
    if (verifyBookingStartOtpError != null) {
      throw verifyBookingStartOtpError!;
    }
    if (verifyBookingStartOtpCompleter != null) {
      await verifyBookingStartOtpCompleter!.future;
    }
    if (onVerifyBookingStartOtp != null) {
      await onVerifyBookingStartOtp!();
    }
  }

  void emitBooking(CanonicalBookingDocumentV3 nextBooking) {
    booking = nextBooking;
    bookingStreamController?.add(
      CanonicalBookingReadModel(
        documentId: nextBooking.bookingIdForTest,
        booking: nextBooking,
      ),
    );
  }
}

CanonicalBookingPrivateData _buildPrivateOtpData({String otpState = 'ACTIVE'}) {
  return CanonicalBookingPrivateData(
    bookingId: 'booking-1',
    parentId: 'parent-1',
    providerId: 'provider-1',
    parentOtpCode: '654321',
    otpState: otpState,
    failedAttemptCount: 0,
    lockedUntil: null,
    verifiedAt: null,
    contactUnlockedAt: null,
    createdAt: null,
    updatedAt: null,
  );
}

CanonicalBookingPrivateParticipantsData _buildPrivateParticipantsData({
  String exactAddress = '221B Baker Street, Bengaluru, Karnataka',
  double? latitude = 12.9716,
  double? longitude = 77.5946,
  String providerPhoneNumber = '9876543210',
}) {
  return CanonicalBookingPrivateParticipantsData(
    bookingId: 'booking-1',
    parentId: 'parent-1',
    providerId: 'provider-1',
    unlockedAfterPaidOnly: true,
    fullName: 'Nisha Gautam',
    phoneNumber: '9123456789',
    email: 'nisha@example.com',
    exactAddress: exactAddress,
    latitude: latitude,
    longitude: longitude,
    providerPhoneNumber: providerPhoneNumber,
    createdAt: null,
    updatedAt: null,
  );
}

CanonicalBookingDocumentV3 _buildConfirmedBooking() {
  final scheduledStartAt = DateTime.utc(2026, 7, 28, 3, 30);
  final scheduledEndAt = DateTime.utc(2026, 7, 28, 4, 30);
  return _buildConfirmedBookingDocument(
    bookingType: BookingV3Type.slot,
    service: const BookingServiceSnapshotV3(
      serviceId: 'service-1',
      providerId: 'provider-1',
      serviceTitle: 'Daily Dog Walk',
      animalType: 'Dog',
      category: 'Walking',
      bookingType: BookingV3Type.slot,
      timezone: 'Asia/Kolkata',
      serviceUnitPricePaise: 25000,
      durationMinutes: 60,
      pricePerNightPaise: null,
      selectedSlotCount: 1,
      totalDurationMinutes: 60,
      checkInDateTime: null,
      checkOutDateTime: null,
      capacitySnapshot: 1,
      serviceLocationType: 'provider_location',
      currency: 'INR',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: scheduledStartAt,
      timezone: 'Asia/Kolkata',
      slots: [
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-1',
          dateKey: '2026-07-28',
          startAt: scheduledStartAt,
          endAt: scheduledEndAt,
          durationMinutes: 60,
          unitPricePaise: 25000,
          serviceId: 'service-1',
          providerId: 'provider-1',
          timezone: 'Asia/Kolkata',
        ),
      ],
      slotCount: 1,
      scheduledStartAt: scheduledStartAt,
      scheduledEndAt: scheduledEndAt,
      totalDurationMinutes: 60,
    ),
    statistics: const CanonicalBookingStatisticsV3(
      selectedSlotCount: 1,
      totalDurationMinutes: 60,
      nights: null,
    ),
    serviceAnchorAt: scheduledStartAt,
    scheduledStartAt: scheduledStartAt,
    checkInDateTime: null,
  );
}

CanonicalBookingDocumentV3 _buildMultiSlotConfirmedBooking() {
  final firstSlotStartAt = DateTime.utc(2026, 7, 28, 3, 30);
  final secondSlotEndAt = DateTime.utc(2026, 7, 28, 5, 30);

  return _buildConfirmedBookingDocument(
    bookingType: BookingV3Type.slot,
    service: const BookingServiceSnapshotV3(
      serviceId: 'service-1',
      providerId: 'provider-1',
      serviceTitle: 'Daily Dog Walk',
      animalType: 'Dog',
      category: 'Walking',
      bookingType: BookingV3Type.slot,
      timezone: 'Asia/Kolkata',
      serviceUnitPricePaise: 25000,
      durationMinutes: 60,
      pricePerNightPaise: null,
      selectedSlotCount: 2,
      totalDurationMinutes: 120,
      checkInDateTime: null,
      checkOutDateTime: null,
      capacitySnapshot: 1,
      serviceLocationType: 'provider_location',
      currency: 'INR',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: firstSlotStartAt,
      timezone: 'Asia/Kolkata',
      slots: [
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-1',
          dateKey: '2026-07-28',
          startAt: firstSlotStartAt,
          endAt: DateTime.utc(2026, 7, 28, 4, 30),
          durationMinutes: 60,
          unitPricePaise: 25000,
          serviceId: 'service-1',
          providerId: 'provider-1',
          timezone: 'Asia/Kolkata',
        ),
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-2',
          dateKey: '2026-07-28',
          startAt: DateTime.utc(2026, 7, 28, 4, 30),
          endAt: secondSlotEndAt,
          durationMinutes: 60,
          unitPricePaise: 25000,
          serviceId: 'service-1',
          providerId: 'provider-1',
          timezone: 'Asia/Kolkata',
        ),
      ],
      slotCount: 2,
      scheduledStartAt: firstSlotStartAt,
      scheduledEndAt: secondSlotEndAt,
      totalDurationMinutes: 120,
    ),
    statistics: const CanonicalBookingStatisticsV3(
      selectedSlotCount: 2,
      totalDurationMinutes: 120,
      nights: null,
    ),
    serviceAnchorAt: firstSlotStartAt,
    scheduledStartAt: firstSlotStartAt,
    checkInDateTime: null,
  );
}

CanonicalBookingDocumentV3 _buildRangeConfirmedBooking() {
  final checkInDateTime = DateTime.utc(2026, 7, 29, 10, 0);
  final checkOutDateTime = DateTime.utc(2026, 7, 31, 6, 0);

  return _buildConfirmedBookingDocument(
    bookingType: BookingV3Type.range,
    service: const BookingServiceSnapshotV3(
      serviceId: 'service-1',
      providerId: 'provider-1',
      serviceTitle: 'Daily Dog Walk',
      animalType: 'Dog',
      category: 'Walking',
      bookingType: BookingV3Type.range,
      timezone: 'Asia/Kolkata',
      serviceUnitPricePaise: 25000,
      durationMinutes: null,
      pricePerNightPaise: 25000,
      selectedSlotCount: null,
      totalDurationMinutes: null,
      checkInDateTime: null,
      checkOutDateTime: null,
      capacitySnapshot: 1,
      serviceLocationType: 'provider_location',
      currency: 'INR',
      snapshotVersion: 1,
    ),
    schedule: CanonicalRangeBookingScheduleV3(
      serviceAnchorAt: checkInDateTime,
      timezone: 'Asia/Kolkata',
      checkInDateTime: checkInDateTime,
      checkOutDateTime: checkOutDateTime,
      nights: 2,
      minNightsSnapshot: 1,
      maxNightsSnapshot: 7,
      maxConcurrentPetsSnapshot: 2,
      petQuantity: 1,
    ),
    statistics: const CanonicalBookingStatisticsV3(
      selectedSlotCount: null,
      totalDurationMinutes: null,
      nights: 2,
    ),
    serviceAnchorAt: checkInDateTime,
    scheduledStartAt: null,
    checkInDateTime: checkInDateTime,
  );
}

CanonicalBookingDocumentV3 _buildMalformedSlotConfirmedBooking() {
  final scheduledStartAt = DateTime.utc(2026, 7, 28, 3, 30);

  return _buildConfirmedBookingDocument(
    bookingType: BookingV3Type.slot,
    service: const BookingServiceSnapshotV3(
      serviceId: 'service-1',
      providerId: 'provider-1',
      serviceTitle: 'Daily Dog Walk',
      animalType: 'Dog',
      category: 'Walking',
      bookingType: BookingV3Type.slot,
      timezone: 'Asia/Kolkata',
      serviceUnitPricePaise: 25000,
      durationMinutes: 60,
      pricePerNightPaise: null,
      selectedSlotCount: 1,
      totalDurationMinutes: 60,
      checkInDateTime: null,
      checkOutDateTime: null,
      capacitySnapshot: 1,
      serviceLocationType: 'provider_location',
      currency: 'INR',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: scheduledStartAt,
      timezone: 'Asia/Kolkata',
      slots: const <CanonicalBookingSlotSegmentV3>[],
      slotCount: 1,
      scheduledStartAt: scheduledStartAt,
      scheduledEndAt: DateTime.utc(2026, 7, 28, 3, 0),
      totalDurationMinutes: 60,
    ),
    statistics: const CanonicalBookingStatisticsV3(
      selectedSlotCount: 1,
      totalDurationMinutes: 60,
      nights: null,
    ),
    serviceAnchorAt: scheduledStartAt,
    scheduledStartAt: scheduledStartAt,
    checkInDateTime: null,
  );
}

CanonicalBookingDocumentV3 _buildConfirmedBookingDocument({
  required BookingV3Type bookingType,
  required BookingServiceSnapshotV3 service,
  required CanonicalBookingScheduleV3 schedule,
  required CanonicalBookingStatisticsV3 statistics,
  required DateTime serviceAnchorAt,
  required DateTime? scheduledStartAt,
  required DateTime? checkInDateTime,
}) {
  final paidAt = DateTime.utc(2026, 7, 27, 8, 0);

  return CanonicalBookingDocumentV3(
    schemaVersion: canonicalBookingSchemaVersion,
    bookingModelVersion: canonicalBookingModelVersion,
    documentFormat: canonicalBookingDocumentFormat,
    bookingType: bookingType,
    state: CanonicalBookingStateV3.confirmed,
    participants: const CanonicalBookingParticipantsV3(
      parent: CanonicalPublicParentParticipantV3(
        parentId: 'parent-1',
        displayFirstName: 'Nisha',
        lastInitial: 'G',
        photoUrl: '',
        completedBookingCount: 4,
        rating: 4.8,
      ),
      provider: CanonicalPublicProviderParticipantV3(
        providerId: 'provider-1',
        displayName: 'Prakash Gautam',
        username: 'prakashg',
        photoUrl: '',
        completedBookingCount: 12,
        rating: 4.9,
      ),
    ),
    service: service,
    schedule: schedule,
    lifecycle: CanonicalBookingLifecycleV3(
      requestedAt: DateTime.utc(2026, 7, 26, 10),
      timerStartsAt: DateTime.utc(2026, 7, 26, 10, 5),
      wasQueuedOutsideWorkingHours: false,
      notifiedAt: DateTime.utc(2026, 7, 26, 10, 6),
      acceptDeadlineAt: DateTime.utc(2026, 7, 26, 11),
      viewedByProviderAt: DateTime.utc(2026, 7, 26, 10, 15),
      respondedAt: DateTime.utc(2026, 7, 26, 10, 30),
      providerResponseType: ProviderResponseTypeV3.accept,
      responseSeconds: 1800,
      payDeadlineAt: DateTime.utc(2026, 7, 27, 11),
      paymentStartedAt: DateTime.utc(2026, 7, 27, 7, 55),
      paidAt: paidAt,
      paymentSeconds: 120,
      otpGeneratedAt: paidAt,
      otpEnteredAt: null,
      noShowAt: null,
      serviceEndedAt: null,
      disputeDeadlineAt: null,
      completedAt: null,
      reviewWindowEndsAt: null,
      finalizedAt: paidAt,
      cancelledAt: null,
    ),
    payment: const CanonicalBookingPaymentV3(
      status: 'confirmed',
      razorpayOrderId: 'order_123',
      razorpayPaymentId: 'pay_123',
      razorpayRefundId: '',
      paymentAttemptId: 'attempt-1',
      orderCreatedAt: null,
      paymentStartedAt: null,
      capturedAt: null,
      verifiedAt: null,
      verificationSource: 'server',
      webhookEventIds: <String>[],
      failureCode: '',
      failureMessage: '',
    ),
    financials: const BookingFinancialSnapshotV3(
      currency: 'INR',
      serviceSubtotalPaise: 25000,
      couponDiscountPaise: 0,
      customerPaidPaise: 25000,
      platformCommissionRateBasisPoints: 1500,
      platformCommissionPaise: 3750,
      providerPayoutPaise: 20000,
      pettxoCouponFundingPaise: 0,
      gatewayFeeSunkPaise: 0,
      providerFaultCostPaise: 0,
      refundAmountPaise: 0,
      pettxoNetBeforeGatewayPaise: 5000,
      pricingVersion: 1,
    ),
    privacy: CanonicalBookingPrivacyV3(
      isPaidContactUnlocked: true,
      contactUnlockedAt: paidAt,
      chatUnlockedAt: paidAt,
      otpVisibleToParent: true,
      exactAddressUnlocked: true,
      privacyVersion: 1,
      privateParticipantsRefPath: 'bookingPrivateParticipants/booking-1',
    ),
    cancellation: const CanonicalBookingCancellationV3(
      cancelledAt: null,
      cancelledBy: null,
      cancelReasonCode: '',
      cancelReasonText: '',
      hoursBeforeServiceAtCancel: null,
      refundBand: '',
      refundBasisPoints: null,
      refundAmountPaise: 0,
      providerCompensationPaise: 0,
      pettxoRetainedPaise: 0,
      cancellationType: null,
    ),
    dispute: const CanonicalBookingDisputeV3(
      disputeId: '',
      status: 'none',
      raisedAt: null,
      raisedBy: null,
      reasonCode: '',
      description: '',
      evidenceRefs: <String>[],
      resolvedAt: null,
      resolvedBy: null,
      resolution: '',
      resolutionVersion: 0,
      financialAdjustmentId: '',
      refundInstructionId: '',
      customerRefundPaise: 0,
      providerReleasePaise: 0,
    ),
    payout: const CanonicalBookingPayoutV3(
      status: 'not_eligible',
      holdReason: '',
      eligibleAt: null,
      readyAt: null,
      processingAt: null,
      releasedAt: null,
      failedAt: null,
      providerPayoutPaise: 0,
      priorPaidPaise: 0,
      remainingPayablePaise: 0,
      payoutReference: '',
      externalTransactionId: '',
      failureCode: '',
      retryCount: 0,
    ),
    statistics: statistics,
    audit: const CanonicalBookingAuditV3(
      createdBy: BookingActorV3.system,
      lastUpdatedBy: BookingActorV3.system,
      source: 'test',
    ),
    parentId: 'parent-1',
    providerId: 'provider-1',
    serviceId: service.serviceId,
    stateQueryValue: CanonicalBookingStateV3.confirmed,
    bookingTypeQueryValue: bookingType,
    serviceAnchorAt: serviceAnchorAt,
    scheduledStartAt: scheduledStartAt,
    checkInDateTime: checkInDateTime,
    acceptDeadlineAt: DateTime.utc(2026, 7, 26, 11),
    payDeadlineAt: DateTime.utc(2026, 7, 27, 11),
    completedAt: null,
    customerId: 'parent-1',
    serviceOwnerId: service.providerId,
    createdAt: DateTime.utc(2026, 7, 26, 10),
    updatedAt: paidAt,
  );
}

CanonicalBookingDocumentV3 _buildInProgressBooking() {
  final scheduledStartAt = DateTime.utc(2026, 7, 28, 3, 30);
  final scheduledEndAt = DateTime.utc(2026, 7, 28, 4, 30);
  final paidAt = DateTime.utc(2026, 7, 27, 8, 0);
  final otpEnteredAt = DateTime.utc(2026, 7, 28, 3, 35);

  return CanonicalBookingDocumentV3(
    schemaVersion: canonicalBookingSchemaVersion,
    bookingModelVersion: canonicalBookingModelVersion,
    documentFormat: canonicalBookingDocumentFormat,
    bookingType: BookingV3Type.slot,
    state: CanonicalBookingStateV3.inProgress,
    participants: const CanonicalBookingParticipantsV3(
      parent: CanonicalPublicParentParticipantV3(
        parentId: 'parent-1',
        displayFirstName: 'Nisha',
        lastInitial: 'G',
        photoUrl: '',
        completedBookingCount: 4,
        rating: 4.8,
      ),
      provider: CanonicalPublicProviderParticipantV3(
        providerId: 'provider-1',
        displayName: 'Prakash Gautam',
        username: 'prakashg',
        photoUrl: '',
        completedBookingCount: 12,
        rating: 4.9,
      ),
    ),
    service: const BookingServiceSnapshotV3(
      serviceId: 'service-1',
      providerId: 'provider-1',
      serviceTitle: 'Daily Dog Walk',
      animalType: 'Dog',
      category: 'Walking',
      bookingType: BookingV3Type.slot,
      timezone: 'Asia/Kolkata',
      serviceUnitPricePaise: 25000,
      durationMinutes: 60,
      pricePerNightPaise: null,
      selectedSlotCount: 1,
      totalDurationMinutes: 60,
      checkInDateTime: null,
      checkOutDateTime: null,
      capacitySnapshot: 1,
      serviceLocationType: 'provider_location',
      currency: 'INR',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: scheduledStartAt,
      timezone: 'Asia/Kolkata',
      slots: [
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-1',
          dateKey: '2026-07-28',
          startAt: scheduledStartAt,
          endAt: scheduledEndAt,
          durationMinutes: 60,
          unitPricePaise: 25000,
          serviceId: 'service-1',
          providerId: 'provider-1',
          timezone: 'Asia/Kolkata',
        ),
      ],
      slotCount: 1,
      scheduledStartAt: scheduledStartAt,
      scheduledEndAt: scheduledEndAt,
      totalDurationMinutes: 60,
    ),
    lifecycle: CanonicalBookingLifecycleV3(
      requestedAt: DateTime.utc(2026, 7, 26, 10),
      timerStartsAt: DateTime.utc(2026, 7, 26, 10, 5),
      wasQueuedOutsideWorkingHours: false,
      notifiedAt: DateTime.utc(2026, 7, 26, 10, 6),
      acceptDeadlineAt: DateTime.utc(2026, 7, 26, 11),
      viewedByProviderAt: DateTime.utc(2026, 7, 26, 10, 15),
      respondedAt: DateTime.utc(2026, 7, 26, 10, 30),
      providerResponseType: ProviderResponseTypeV3.accept,
      responseSeconds: 1800,
      payDeadlineAt: DateTime.utc(2026, 7, 27, 11),
      paymentStartedAt: DateTime.utc(2026, 7, 27, 7, 55),
      paidAt: paidAt,
      paymentSeconds: 120,
      otpGeneratedAt: paidAt,
      otpEnteredAt: otpEnteredAt,
      noShowAt: null,
      serviceEndedAt: null,
      disputeDeadlineAt: null,
      completedAt: null,
      reviewWindowEndsAt: null,
      finalizedAt: paidAt,
      cancelledAt: null,
    ),
    payment: const CanonicalBookingPaymentV3(
      status: 'confirmed',
      razorpayOrderId: 'order_123',
      razorpayPaymentId: 'pay_123',
      razorpayRefundId: '',
      paymentAttemptId: 'attempt-1',
      orderCreatedAt: null,
      paymentStartedAt: null,
      capturedAt: null,
      verifiedAt: null,
      verificationSource: 'server',
      webhookEventIds: <String>[],
      failureCode: '',
      failureMessage: '',
    ),
    financials: const BookingFinancialSnapshotV3(
      currency: 'INR',
      serviceSubtotalPaise: 25000,
      couponDiscountPaise: 0,
      customerPaidPaise: 25000,
      platformCommissionRateBasisPoints: 1500,
      platformCommissionPaise: 3750,
      providerPayoutPaise: 20000,
      pettxoCouponFundingPaise: 0,
      gatewayFeeSunkPaise: 0,
      providerFaultCostPaise: 0,
      refundAmountPaise: 0,
      pettxoNetBeforeGatewayPaise: 5000,
      pricingVersion: 1,
    ),
    privacy: CanonicalBookingPrivacyV3(
      isPaidContactUnlocked: true,
      contactUnlockedAt: paidAt,
      chatUnlockedAt: paidAt,
      otpVisibleToParent: true,
      exactAddressUnlocked: true,
      privacyVersion: 1,
      privateParticipantsRefPath: 'bookingPrivateParticipants/booking-1',
    ),
    cancellation: const CanonicalBookingCancellationV3(
      cancelledAt: null,
      cancelledBy: null,
      cancelReasonCode: '',
      cancelReasonText: '',
      hoursBeforeServiceAtCancel: null,
      refundBand: '',
      refundBasisPoints: null,
      refundAmountPaise: 0,
      providerCompensationPaise: 0,
      pettxoRetainedPaise: 0,
      cancellationType: null,
    ),
    dispute: const CanonicalBookingDisputeV3(
      disputeId: '',
      status: 'none',
      raisedAt: null,
      raisedBy: null,
      reasonCode: '',
      description: '',
      evidenceRefs: <String>[],
      resolvedAt: null,
      resolvedBy: null,
      resolution: '',
      resolutionVersion: 0,
      financialAdjustmentId: '',
      refundInstructionId: '',
      customerRefundPaise: 0,
      providerReleasePaise: 0,
    ),
    payout: const CanonicalBookingPayoutV3(
      status: 'not_eligible',
      holdReason: '',
      eligibleAt: null,
      readyAt: null,
      processingAt: null,
      releasedAt: null,
      failedAt: null,
      providerPayoutPaise: 0,
      priorPaidPaise: 0,
      remainingPayablePaise: 0,
      payoutReference: '',
      externalTransactionId: '',
      failureCode: '',
      retryCount: 0,
    ),
    statistics: const CanonicalBookingStatisticsV3(
      selectedSlotCount: 1,
      totalDurationMinutes: 60,
      nights: null,
    ),
    audit: const CanonicalBookingAuditV3(
      createdBy: BookingActorV3.system,
      lastUpdatedBy: BookingActorV3.system,
      source: 'test',
    ),
    parentId: 'parent-1',
    providerId: 'provider-1',
    serviceId: 'service-1',
    stateQueryValue: CanonicalBookingStateV3.inProgress,
    bookingTypeQueryValue: BookingV3Type.slot,
    serviceAnchorAt: scheduledStartAt,
    scheduledStartAt: scheduledStartAt,
    checkInDateTime: null,
    acceptDeadlineAt: DateTime.utc(2026, 7, 26, 11),
    payDeadlineAt: DateTime.utc(2026, 7, 27, 11),
    completedAt: null,
    customerId: 'parent-1',
    serviceOwnerId: 'provider-1',
    createdAt: DateTime.utc(2026, 7, 26, 10),
    updatedAt: otpEnteredAt,
  );
}

extension on CanonicalBookingDocumentV3 {
  String get bookingIdForTest => 'booking-1';
}
