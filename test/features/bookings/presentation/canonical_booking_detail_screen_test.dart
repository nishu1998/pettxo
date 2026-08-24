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
import 'package:pettexo/features/bookings/domain/models/canonical_booking_refund_models.dart';
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
        final booking = bookingRepository.booking!;
        final schedule = booking.schedule as CanonicalSlotBookingScheduleV3;
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        await _scrollUntilTextVisible(
          tester,
          _calendarDateLabel(schedule.scheduledStartAt),
        );
        expect(
          find.text(_calendarDateLabel(schedule.scheduledStartAt)),
          findsOneWidget,
        );
        expect(
          find.text(
            _timeRangeLabel(schedule.scheduledStartAt, schedule.scheduledEndAt),
          ),
          findsOneWidget,
        );
        expect(find.text('1 hour'), findsOneWidget);
      },
    );

    testWidgets(
      'renders continuous multi-slot bookings as one combined window',
      (tester) async {
        bookingRepository.booking = _buildMultiSlotConfirmedBooking();
        final booking = bookingRepository.booking!;
        final schedule = booking.schedule as CanonicalSlotBookingScheduleV3;
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        await _scrollUntilTextVisible(
          tester,
          _calendarDateLabel(schedule.scheduledStartAt),
        );
        expect(
          find.text(_calendarDateLabel(schedule.scheduledStartAt)),
          findsOneWidget,
        );
        expect(
          find.text(
            _timeRangeLabel(schedule.scheduledStartAt, schedule.scheduledEndAt),
          ),
          findsOneWidget,
        );
        expect(find.text('2 hours'), findsOneWidget);
      },
    );

    testWidgets('renders range booking schedule rows for both booking roles', (
      tester,
    ) async {
      bookingRepository.booking = _buildRangeConfirmedBooking();
      final booking = bookingRepository.booking!;
      final schedule = booking.schedule as CanonicalRangeBookingScheduleV3;
      final privateController = CanonicalBookingPrivateController(
        privateLoader: (_) => Stream.value(_buildPrivateOtpData()),
      );

      await _pumpScreen(
        tester,
        bookingRepository: bookingRepository,
        privateController: privateController,
        currentUserIdOverride: 'provider-1',
      );

      await _scrollUntilTextVisible(
        tester,
        _calendarDateLabel(schedule.checkInDateTime),
      );
      await _scrollUntilTextVisible(tester, 'Booking Type');
      expect(find.text('Stay booking'), findsOneWidget);
      expect(
        find.text(_calendarDateLabel(schedule.checkInDateTime)),
        findsOneWidget,
      );
      expect(
        find.text(
          _timeRangeLabel(schedule.checkInDateTime, schedule.checkOutDateTime),
        ),
        findsOneWidget,
      );
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

    testWidgets(
      'derived no-show hides customer OTP section and shows terminal no-show timeline item',
      (tester) async {
        bookingRepository.booking = _buildOverdueConfirmedBooking();
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) => const Stream.empty(),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        expect(find.text('No Show'), findsOneWidget);
        expect(
          find.text(
            'The service window ended before OTP verification, so this booking was marked as no-show.',
          ),
          findsOneWidget,
        );
        expect(find.text('SERVICE-START OTP'), findsNothing);
        expect(find.text('START OTP'), findsNothing);
        expect(find.text('Use this OTP to start the service'), findsNothing);
        expect(
          find.text(
            'The service OTP is no longer available because this booking was marked as no-show.',
          ),
          findsNothing,
        );
        expect(find.textContaining('Share this with'), findsNothing);
        await _scrollUntilTextVisible(tester, 'BOOKING TIMELINE');
        expect(find.text('Marked as no-show'), findsOneWidget);
        expect(
          find.text('OTP was not verified before the service window ended'),
          findsOneWidget,
        );
        expect(
          find.text(
            _timelineDateTimeLabel(
              (bookingRepository.booking!.schedule
                      as CanonicalSlotBookingScheduleV3)
                  .scheduledEndAt,
            ),
          ),
          findsOneWidget,
        );
        await _scrollUntilTextVisible(tester, 'No-show status');
        expect(
          find.textContaining('Pettxo support can review a dispute until'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'raw no-show customer booking also hides OTP section and uses persisted no-show time',
      (tester) async {
        bookingRepository.booking = _buildRawNoShowBooking();
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'REVOKED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        expect(find.text('SERVICE-START OTP'), findsNothing);
        expect(find.text('START OTP'), findsNothing);
        await _scrollUntilTextVisible(tester, 'BOOKING TIMELINE');
        expect(find.text('Marked as no-show'), findsOneWidget);
        expect(
          find.text(
            _timelineDateTimeLabel(
              bookingRepository.booking!.lifecycle.noShowAt!,
            ),
          ),
          findsOneWidget,
        );
      },
    );

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
      expect(find.text('Enter customer OTP'), findsOneWidget);
      await _scrollUntilTextVisible(tester, 'BOOKING CHAT');
      await tester.ensureVisible(find.text('Message customer'));
      await tester.pump();
      expect(find.text('Message customer'), findsOneWidget);
      expect(
        find.text(
          'Coordinate any remaining service details directly with the customer.',
        ),
        findsOneWidget,
      );
      expect(find.text('Start service'), findsNothing);
      expect(find.text('Service OTP'), findsNothing);
      expect(find.text('654321'), findsNothing);
      expect(find.text('Reveal OTP'), findsNothing);
    });

    testWidgets(
      'provider no-show hides OTP entry controls and ends timeline with no-show outcome',
      (tester) async {
        bookingRepository.booking = _buildRawNoShowBooking();
        bookingRepository.participantPrivateData =
            _buildPrivateParticipantsData();
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'REVOKED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
          currentUserIdOverride: 'provider-1',
        );

        expect(find.text('SERVICE START'), findsNothing);
        expect(find.text('Enter customer OTP'), findsNothing);
        expect(find.text('Verify OTP'), findsNothing);
        await _scrollUntilTextVisible(tester, 'BOOKING TIMELINE');
        expect(find.text('Service scheduled'), findsOneWidget);
        expect(find.text('Marked as no-show'), findsOneWidget);
        expect(
          find.text('OTP was not verified before the service window ended'),
          findsOneWidget,
        );
        expect(find.text('Complete service'), findsNothing);
      },
    );

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
      'provider OTP submit stays enabled after the sheet rebuilds with six visible digits',
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

        final otpField = find.byKey(const ValueKey('provider-otp-input'));
        await tester.enterText(otpField, '123456');
        await tester.pump();

        tester.testTextInput.hide();
        await tester.pumpAndSettle();

        expect(find.text('123456'), findsOneWidget);
        final verifyButton = tester.widget<GradientButton>(
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

        expect(find.text('The OTP is incorrect.'), findsOneWidget);
        expect(find.textContaining('permission-denied'), findsNothing);
        expect(find.textContaining('INVALID_OTP'), findsNothing);
      },
    );

    testWidgets(
      'provider completion success stops spinner after booking moves to completed pending review',
      (tester) async {
        bookingRepository.booking = _buildInProgressBooking();
        bookingRepository.bookingStreamController =
            StreamController<BookingReadModel?>.broadcast();
        bookingRepository.emitBooking(_buildInProgressBooking());
        final completionStarted = Completer<void>();
        final allowCompletion = Completer<void>();
        bookingRepository.onCompleteBookingService = () async {
          completionStarted.complete();
          await allowCompletion.future;
          bookingRepository.booking = _buildCompletedPendingReviewBooking();
          bookingRepository.emitBooking(_buildCompletedPendingReviewBooking());
        };
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'USED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
          currentUserIdOverride: 'provider-1',
        );

        await _scrollToProviderStartSection(
          tester,
          actionText: 'Complete service',
        );
        expect(find.text('Complete service'), findsOneWidget);

        await tester.tap(find.text('Complete service'));
        await tester.pump();
        await completionStarted.future;
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is CircularProgressIndicator &&
                widget.valueColor is AlwaysStoppedAnimation<Color>,
          ),
          findsOneWidget,
        );
        expect(find.text('Complete service'), findsNothing);

        allowCompletion.complete();
        await tester.pumpAndSettle();

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Complete service'), findsNothing);
        expect(
          bookingRepository.booking?.state,
          CanonicalBookingStateV3.completedPendingReview,
        );
      },
    );

    testWidgets(
      'provider completed booking shows redesigned details and hides provider contact',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking();
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
          currentUserIdOverride: 'provider-1',
        );

        expect(find.text('BOOKING SUMMARY'), findsOneWidget);
        await _scrollUntilTextVisible(tester, 'BOOKING TIMELINE');
        expect(find.text('BOOKING TIMELINE'), findsOneWidget);
        await _scrollUntilTextVisible(tester, 'SERVICE LOCATION');
        expect(find.text('SERVICE LOCATION'), findsOneWidget);
        await _scrollUntilTextVisible(tester, 'Customer phone');
        expect(find.text('Customer phone'), findsOneWidget);
        expect(find.text('Provider contact'), findsNothing);
        expect(find.text('Provider phone'), findsNothing);

      },
    );

    testWidgets(
      'customer completed booking hides OTP section and shows redesigned completion actions',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          reviewWindowEndsAt: DateTime.now().add(const Duration(hours: 12)),
        );
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

        expect(find.text('BOOKING SUMMARY'), findsOneWidget);
        expect(find.text('BOOKING STATUS'), findsOneWidget);
        await _scrollUntilTextVisible(tester, 'BOOKING TIMELINE');
        expect(find.text('BOOKING TIMELINE'), findsOneWidget);
        await _scrollUntilTextVisible(tester, 'PRIMARY ACTIONS');
        expect(find.text('Leave review'), findsOneWidget);
        expect(find.text('Raise dispute'), findsOneWidget);
        expect(find.text('SERVICE-START OTP'), findsNothing);
        expect(find.text('START OTP'), findsNothing);
        expect(
          find.text(
            'Service started. Your booking OTP has already been used for this booking.',
          ),
          findsNothing,
        );
        await _scrollUntilTextVisible(tester, 'Message provider');
        expect(find.text('Message provider'), findsOneWidget);
      },
    );

    testWidgets(
      'customer completed booking keeps review available after dispute window expiry',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          reviewWindowEndsAt: DateTime.now().subtract(const Duration(hours: 1)),
        );
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

        await _scrollUntilTextVisible(tester, 'PRIMARY ACTIONS');
        expect(find.text('Leave review'), findsOneWidget);
        expect(find.text('Raise dispute'), findsNothing);
        expect(find.text('PRIMARY ACTIONS'), findsOneWidget);
      },
    );

    testWidgets(
      'open dispute uses canonical layout and dispute-first customer status',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          disputeStatus: 'OPEN',
          disputeRaisedAt: DateTime.utc(2026, 7, 29, 8),
        );
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

        expect(find.text('BOOKING SUMMARY'), findsOneWidget);
        expect(find.text('BOOKING STATUS'), findsOneWidget);
        await _scrollUntilTextVisible(tester, 'BOOKING TIMELINE');
        expect(find.text('BOOKING TIMELINE'), findsOneWidget);
        await _scrollUntilTextVisible(tester, 'DISPUTE STATUS');
        expect(find.text('DISPUTE STATUS'), findsOneWidget);
        expect(find.text('Under dispute'), findsWidgets);
        expect(find.text('Confirmed'), findsNothing);
        expect(find.text('completedPendingReview'), findsNothing);
        expect(find.text('COMPLETED_PENDING_REVIEW'), findsNothing);
      },
    );

    testWidgets(
      'resolved customer-wins dispute shows customer-safe result and refund state',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          disputeStatus: 'RESOLVED',
          disputeResolution: 'CUSTOMER_WINS',
          disputeRaisedAt: DateTime.utc(2026, 7, 29, 8),
          disputeResolvedAt: DateTime.utc(2026, 7, 29, 10),
          customerRefundPaise: 25000,
          providerReleasePaise: 0,
        );
        bookingRepository.refundRecord = const CanonicalBookingRefundRecord(
          bookingId: 'booking-1',
          state: 'confirmed',
          refundAmountPaise: 25000,
          refundInstructionId: 'refund-1',
          razorpayRefundId: 'rfnd_1',
          createdAt: null,
          submittedAt: null,
          confirmedAt: null,
          updatedAt: null,
        );
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'USED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        await _scrollUntilTextVisible(tester, 'DISPUTE RESULT');
        expect(find.text('DISPUTE RESULT'), findsOneWidget);
        expect(find.text('Resolved in your favor'), findsOneWidget);
        expect(find.textContaining('Refunded: ₹250'), findsOneWidget);
        expect(find.text('PROVIDER_WINS'), findsNothing);
      },
    );

    testWidgets(
      'resolved custom-allocation dispute shows customer-safe result and refund state',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          disputeStatus: 'RESOLVED',
          disputeResolution: 'CUSTOM_ALLOCATION',
          disputeRaisedAt: DateTime.utc(2026, 7, 29, 8),
          disputeResolvedAt: DateTime.utc(2026, 7, 29, 10),
          customerRefundPaise: 4500,
          providerReleasePaise: 15500,
        );
        bookingRepository.refundRecord = const CanonicalBookingRefundRecord(
          bookingId: 'booking-1',
          state: 'pending',
          refundAmountPaise: 4500,
          refundInstructionId: 'refund-1',
          razorpayRefundId: '',
          createdAt: null,
          submittedAt: null,
          confirmedAt: null,
          updatedAt: null,
        );
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'USED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        await _scrollUntilTextVisible(tester, 'DISPUTE RESULT');
        expect(find.text('DISPUTE RESULT'), findsOneWidget);
        expect(find.text('Partial refund'), findsOneWidget);
        expect(find.text('45%'), findsNothing);
        expect(find.textContaining('Refund approved'), findsOneWidget);
        expect(find.textContaining('Status: Processing.'), findsOneWidget);
        expect(find.text('provider final entitlement'), findsNothing);
        expect(find.text('CUSTOM_ALLOCATION'), findsNothing);
      },
    );

    testWidgets(
      'resolved dispute shows provider-safe result and settlement status',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          disputeStatus: 'RESOLVED',
          disputeResolution: 'PROVIDER_WINS',
          disputeRaisedAt: DateTime.utc(2026, 7, 29, 8),
          disputeResolvedAt: DateTime.utc(2026, 7, 29, 10),
          customerRefundPaise: 0,
          providerReleasePaise: 25000,
          payoutStatus: 'PROCESSING',
        );
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
          currentUserIdOverride: 'provider-1',
        );

        await _scrollUntilTextVisible(tester, 'DISPUTE RESULT');
        expect(find.text('DISPUTE RESULT'), findsOneWidget);
        expect(find.text('Resolved in your favor'), findsOneWidget);
        expect(find.text('Settlement status'), findsOneWidget);
        expect(find.text('Processing'), findsWidgets);
        expect(find.text('Pettxo retained amount'), findsNothing);
        expect(find.text('CUSTOMER_WINS'), findsNothing);
      },
    );

    testWidgets(
      'customer completed booking hides Leave Review when review is already submitted',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          reviewWindowEndsAt: DateTime.now().add(const Duration(hours: 12)),
          reviewSubmitted: true,
        );
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'USED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        await _scrollUntilTextVisible(tester, 'PRIMARY ACTIONS');
        expect(find.text('Leave review'), findsNothing);
        expect(find.text('Raise dispute'), findsOneWidget);
      },
    );

    testWidgets(
      'customer completed booking submits review once and immediately hides the review action',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          reviewWindowEndsAt: DateTime.now().add(const Duration(hours: 12)),
        );
        bookingRepository.submitBookingReviewResult = 'booking-1';
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'USED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        await _scrollUntilTextVisible(tester, 'Leave review');
        await tester.ensureVisible(find.text('Leave review'));
        await tester.pump();
        await tester.tap(find.text('Leave review'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(IconButton).last);
        await tester.enterText(
          find.byType(TextField).last,
          'Excellent completed booking experience.',
        );
        await tester.tap(find.widgetWithText(GradientButton, 'Submit review'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(bookingRepository.submitBookingReviewCallCount, 1);
        expect(bookingRepository.lastReviewBookingId, 'booking-1');
        expect(bookingRepository.lastReviewRating, 5);
        expect(
          bookingRepository.lastReviewComment,
          'Excellent completed booking experience.',
        );
        expect(find.text('Review submitted successfully.'), findsOneWidget);
        expect(find.text('Leave review'), findsNothing);
      },
    );

    testWidgets(
      'customer completed booking maps duplicate review response to already reviewed and hides action',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          reviewWindowEndsAt: DateTime.now().add(const Duration(hours: 12)),
        );
        bookingRepository.submitBookingReviewError = FirebaseFunctionsException(
          code: 'already-exists',
          message: 'A review has already been submitted for this booking.',
          details: {'code': 'REVIEW_ALREADY_SUBMITTED'},
        );
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'USED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        await _scrollUntilTextVisible(tester, 'Leave review');
        await tester.ensureVisible(find.text('Leave review'));
        await tester.pump();
        await tester.tap(find.text('Leave review'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(IconButton).last);
        await tester.enterText(
          find.byType(TextField).last,
          'Excellent completed booking experience.',
        );
        await tester.tap(find.widgetWithText(GradientButton, 'Submit review'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          find.text('Your review has already been submitted for this booking.'),
          findsOneWidget,
        );
        expect(find.text('Leave review'), findsNothing);
      },
    );

    testWidgets(
      'customer completed booking submits dispute payload and shows success state',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          reviewWindowEndsAt: DateTime.now().add(const Duration(hours: 12)),
        );
        bookingRepository.createBookingDisputeResult = 'dispute-1';
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'USED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        await _scrollUntilTextVisible(tester, 'Raise dispute');
        await tester.tap(find.text('Raise dispute'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).at(0),
          'provider_no_show',
        );
        await tester.enterText(
          find.byType(TextField).at(1),
          'The provider did not arrive at the booked time.',
        );
        await tester.tap(find.widgetWithText(GradientButton, 'Raise dispute'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(bookingRepository.createBookingDisputeCallCount, 1);
        expect(bookingRepository.lastDisputeBookingId, 'booking-1');
        expect(bookingRepository.lastDisputeReason, 'provider_no_show');
        expect(
          bookingRepository.lastDisputeDescription,
          'The provider did not arrive at the booked time.',
        );
        expect(
          find.text(
            'Dispute submitted. Payout stays on hold until Pettxo reviews it.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'customer completed booking maps already disputed errors clearly',
      (tester) async {
        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          reviewWindowEndsAt: DateTime.now().add(const Duration(hours: 12)),
        );
        bookingRepository.createBookingDisputeError =
            FirebaseFunctionsException(
              code: 'already-exists',
              message: 'A dispute already exists for this booking.',
              details: {'code': 'ALREADY_DISPUTED'},
            );
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'USED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        await _scrollUntilTextVisible(tester, 'Raise dispute');
        await tester.tap(find.text('Raise dispute'));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).at(0),
          'provider_no_show',
        );
        await tester.enterText(
          find.byType(TextField).at(1),
          'The provider did not arrive at the booked time.',
        );
        await tester.tap(find.widgetWithText(GradientButton, 'Raise dispute'));
        await tester.pump();
        await tester.pumpAndSettle();

        expect(
          find.text('A dispute has already been raised for this booking.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'small-screen completed dispute layout avoids overflow and raw status leakage',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        bookingRepository.booking = _buildCompletedPendingReviewBooking(
          disputeStatus: 'RESOLVED',
          disputeResolution: 'CUSTOM_ALLOCATION',
          disputeRaisedAt: DateTime.utc(2026, 7, 29, 8),
          disputeResolvedAt: DateTime.utc(2026, 7, 29, 10),
          customerRefundPaise: 4500,
          providerReleasePaise: 15500,
          payoutStatus: 'PROCESSING',
        );
        bookingRepository.refundRecord = const CanonicalBookingRefundRecord(
          bookingId: 'booking-1',
          state: 'pending',
          refundAmountPaise: 4500,
          refundInstructionId: 'refund-1',
          razorpayRefundId: '',
          createdAt: null,
          submittedAt: null,
          confirmedAt: null,
          updatedAt: null,
        );
        final privateController = CanonicalBookingPrivateController(
          privateLoader: (_) =>
              Stream.value(_buildPrivateOtpData(otpState: 'USED')),
        );

        await _pumpScreen(
          tester,
          bookingRepository: bookingRepository,
          privateController: privateController,
        );

        await _scrollUntilTextVisible(tester, 'IMPORTANT INFORMATION');
        expect(tester.takeException(), isNull);
        expect(find.text('completedPendingReview'), findsNothing);
        expect(find.text('COMPLETED_PENDING_REVIEW'), findsNothing);
        expect(find.text('CUSTOM_ALLOCATION'), findsNothing);
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

Future<void> _scrollToProviderStartSection(
  WidgetTester tester, {
  String actionText = 'Enter customer OTP',
}) async {
  await _scrollUntilTextVisible(tester, 'SERVICE START');
  final actionFinder = find.text(actionText);
  if (actionFinder.evaluate().isNotEmpty) {
    await tester.ensureVisible(actionFinder);
    await tester.pump();
  }
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
  CanonicalBookingRefundRecord? refundRecord;
  Stream<CanonicalBookingPrivateParticipantsData?>? participantPrivateStream;
  StreamController<BookingReadModel?>? bookingStreamController;
  Completer<void>? verifyBookingStartOtpCompleter;
  Future<void> Function()? onVerifyBookingStartOtp;
  Future<void> Function()? onCompleteBookingService;
  Object? submitBookingReviewError;
  Object? createBookingDisputeError;
  Object? verifyBookingStartOtpError;
  Object? completeBookingServiceError;
  int submitBookingReviewCallCount = 0;
  int createBookingDisputeCallCount = 0;
  int verifyBookingStartOtpCallCount = 0;
  int completeBookingServiceCallCount = 0;
  String submitBookingReviewResult = '';
  String createBookingDisputeResult = '';
  String lastReviewBookingId = '';
  int lastReviewRating = 0;
  String lastReviewComment = '';
  String lastDisputeBookingId = '';
  String lastDisputeReason = '';
  String lastDisputeDescription = '';
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
  Stream<CanonicalBookingRefundRecord?> watchCanonicalBookingRefund(
    String bookingId,
  ) => Stream.value(refundRecord);

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

  @override
  Future<void> completeBookingServiceV3({required String bookingId}) async {
    completeBookingServiceCallCount += 1;
    if (completeBookingServiceError != null) {
      throw completeBookingServiceError!;
    }
    if (onCompleteBookingService != null) {
      await onCompleteBookingService!();
    }
  }

  @override
  Future<String> submitBookingReviewV3({
    required String bookingId,
    required int rating,
    String comment = '',
    List<String> tags = const [],
  }) async {
    submitBookingReviewCallCount += 1;
    lastReviewBookingId = bookingId;
    lastReviewRating = rating;
    lastReviewComment = comment;
    if (submitBookingReviewError != null) {
      throw submitBookingReviewError!;
    }
    return submitBookingReviewResult;
  }

  @override
  Future<String> createBookingDisputeV3({
    required String bookingId,
    required String reason,
    required String description,
    List<UploadedBookingDisputeEvidence> evidence = const [],
  }) async {
    createBookingDisputeCallCount += 1;
    lastDisputeBookingId = bookingId;
    lastDisputeReason = reason;
    lastDisputeDescription = description;
    if (createBookingDisputeError != null) {
      throw createBookingDisputeError!;
    }
    return createBookingDisputeResult;
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

DateTime _futureFixtureUtc({
  required int daysFromNow,
  required int hour,
  int minute = 0,
}) {
  final now = DateTime.now().toUtc();
  final anchor = DateTime.utc(now.year, now.month, now.day);
  return anchor.add(Duration(days: daysFromNow, hours: hour, minutes: minute));
}

String _calendarDateLabel(DateTime value) {
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
  final local = value.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour > 12
      ? local.hour - 12
      : (local.hour == 0 ? 12 : local.hour);
  final minutes = local.minute.toString().padLeft(2, '0');
  final meridiem = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minutes $meridiem';
}

String _timeRangeLabel(DateTime start, DateTime end) {
  return '${_timeLabel(start)} - ${_timeLabel(end)}';
}

String _timelineDateTimeLabel(DateTime value) {
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
  final local = value.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year} · ${_timeLabel(value)}';
}

CanonicalBookingDocumentV3 _buildConfirmedBooking() {
  final scheduledStartAt = _futureFixtureUtc(
    daysFromNow: 2,
    hour: 3,
    minute: 30,
  );
  final scheduledEndAt = scheduledStartAt.add(const Duration(hours: 1));
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
      schedulingMode: 'fixedDuration',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: scheduledStartAt,
      timezone: 'Asia/Kolkata',
      slots: [
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-1',
          dateKey:
              '${scheduledStartAt.year.toString().padLeft(4, '0')}-'
              '${scheduledStartAt.month.toString().padLeft(2, '0')}-'
              '${scheduledStartAt.day.toString().padLeft(2, '0')}',
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
  final firstSlotStartAt = _futureFixtureUtc(
    daysFromNow: 2,
    hour: 3,
    minute: 30,
  );
  final secondSlotEndAt = firstSlotStartAt.add(const Duration(hours: 2));
  final dateKey =
      '${firstSlotStartAt.year.toString().padLeft(4, '0')}-'
      '${firstSlotStartAt.month.toString().padLeft(2, '0')}-'
      '${firstSlotStartAt.day.toString().padLeft(2, '0')}';

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
      schedulingMode: 'fixedDuration',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: firstSlotStartAt,
      timezone: 'Asia/Kolkata',
      slots: [
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-1',
          dateKey: dateKey,
          startAt: firstSlotStartAt,
          endAt: firstSlotStartAt.add(const Duration(hours: 1)),
          durationMinutes: 60,
          unitPricePaise: 25000,
          serviceId: 'service-1',
          providerId: 'provider-1',
          timezone: 'Asia/Kolkata',
        ),
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-2',
          dateKey: dateKey,
          startAt: firstSlotStartAt.add(const Duration(hours: 1)),
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
  final checkInDateTime = _futureFixtureUtc(daysFromNow: 2, hour: 10);
  final checkOutDateTime = checkInDateTime.add(
    const Duration(days: 1, hours: 20),
  );

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
      schedulingMode: 'fixedDuration',
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
  final scheduledStartAt = _futureFixtureUtc(
    daysFromNow: 2,
    hour: 3,
    minute: 30,
  );

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
      schedulingMode: 'fixedDuration',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: scheduledStartAt,
      timezone: 'Asia/Kolkata',
      slots: const <CanonicalBookingSlotSegmentV3>[],
      slotCount: 1,
      scheduledStartAt: scheduledStartAt,
      scheduledEndAt: scheduledStartAt.subtract(const Duration(minutes: 30)),
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

CanonicalBookingDocumentV3 _buildOverdueConfirmedBooking() {
  final scheduledStartAt = _futureFixtureUtc(
    daysFromNow: -2,
    hour: 3,
    minute: 30,
  );
  final scheduledEndAt = scheduledStartAt.add(const Duration(hours: 1));
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
      schedulingMode: 'fixedDuration',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: scheduledStartAt,
      timezone: 'Asia/Kolkata',
      slots: [
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-1',
          dateKey:
              '${scheduledStartAt.year.toString().padLeft(4, '0')}-'
              '${scheduledStartAt.month.toString().padLeft(2, '0')}-'
              '${scheduledStartAt.day.toString().padLeft(2, '0')}',
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

CanonicalBookingDocumentV3 _buildConfirmedBookingDocument({
  required BookingV3Type bookingType,
  required BookingServiceSnapshotV3 service,
  required CanonicalBookingScheduleV3 schedule,
  required CanonicalBookingStatisticsV3 statistics,
  required DateTime serviceAnchorAt,
  required DateTime? scheduledStartAt,
  required DateTime? checkInDateTime,
  CanonicalBookingStateV3 state = CanonicalBookingStateV3.confirmed,
  DateTime? noShowAt,
  DateTime? disputeDeadlineAt,
  bool otpVisibleToParent = true,
  DateTime? paidAtOverride,
  DateTime? contactUnlockedAtOverride,
  DateTime? chatUnlockedAtOverride,
  bool? isPaidContactUnlockedOverride,
  String parentDisplayFirstName = 'Nisha',
  String parentLastInitial = 'G',
  bool includePaidLifecycle = true,
}) {
  final requestedAt = serviceAnchorAt.subtract(const Duration(days: 2));
  final paidAt =
      paidAtOverride ??
      serviceAnchorAt.subtract(const Duration(days: 1, hours: 1));
  final contactUnlockedAt = contactUnlockedAtOverride ?? paidAt;
  final chatUnlockedAt = chatUnlockedAtOverride ?? paidAt;
  final isPaidContactUnlocked = isPaidContactUnlockedOverride ?? true;

  return CanonicalBookingDocumentV3(
    schemaVersion: canonicalBookingSchemaVersion,
    bookingModelVersion: canonicalBookingModelVersion,
    documentFormat: canonicalBookingDocumentFormat,
    bookingType: bookingType,
    state: state,
    participants: CanonicalBookingParticipantsV3(
      parent: CanonicalPublicParentParticipantV3(
        parentId: 'parent-1',
        displayFirstName: parentDisplayFirstName,
        lastInitial: parentLastInitial,
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
      requestedAt: requestedAt,
      timerStartsAt: requestedAt.add(const Duration(minutes: 5)),
      wasQueuedOutsideWorkingHours: false,
      notifiedAt: requestedAt.add(const Duration(minutes: 6)),
      acceptDeadlineAt: requestedAt.add(const Duration(hours: 1)),
      viewedByProviderAt: requestedAt.add(const Duration(minutes: 15)),
      respondedAt: requestedAt.add(const Duration(minutes: 30)),
      providerResponseType: ProviderResponseTypeV3.accept,
      responseSeconds: 1800,
      payDeadlineAt: requestedAt.add(const Duration(days: 1, hours: 1)),
      paymentStartedAt: includePaidLifecycle
          ? paidAt.subtract(const Duration(minutes: 5))
          : null,
      paidAt: includePaidLifecycle ? paidAt : paidAtOverride,
      paymentSeconds: 120,
      otpGeneratedAt: includePaidLifecycle ? paidAt : null,
      otpEnteredAt: null,
      noShowAt: noShowAt,
      serviceEndedAt: null,
      disputeDeadlineAt: disputeDeadlineAt,
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
      isPaidContactUnlocked: isPaidContactUnlocked,
      contactUnlockedAt: includePaidLifecycle
          ? contactUnlockedAt
          : contactUnlockedAtOverride,
      chatUnlockedAt: includePaidLifecycle
          ? chatUnlockedAt
          : chatUnlockedAtOverride,
      otpVisibleToParent: otpVisibleToParent,
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
    stateQueryValue: state,
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

CanonicalBookingDocumentV3 _buildRawNoShowBooking() {
  final scheduledStartAt = _futureFixtureUtc(
    daysFromNow: -2,
    hour: 3,
    minute: 30,
  );
  final scheduledEndAt = scheduledStartAt.add(const Duration(hours: 1));
  return _buildConfirmedBookingDocument(
    bookingType: BookingV3Type.slot,
    state: CanonicalBookingStateV3.noShow,
    noShowAt: scheduledEndAt,
    disputeDeadlineAt: scheduledEndAt.add(const Duration(hours: 24)),
    otpVisibleToParent: false,
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
      schedulingMode: 'fixedDuration',
      snapshotVersion: 1,
    ),
    schedule: CanonicalSlotBookingScheduleV3(
      serviceAnchorAt: scheduledStartAt,
      timezone: 'Asia/Kolkata',
      slots: [
        CanonicalBookingSlotSegmentV3(
          slotId: 'slot-1',
          dateKey:
              '${scheduledStartAt.year.toString().padLeft(4, '0')}-'
              '${scheduledStartAt.month.toString().padLeft(2, '0')}-'
              '${scheduledStartAt.day.toString().padLeft(2, '0')}',
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

CanonicalBookingDocumentV3 _buildInProgressBooking({DateTime? otpEnteredAt}) {
  final scheduledStartAt = DateTime.utc(2026, 7, 28, 3, 30);
  final scheduledEndAt = DateTime.utc(2026, 7, 28, 4, 30);
  final paidAt = DateTime.utc(2026, 7, 27, 8, 0);
  final effectiveOtpEnteredAt =
      otpEnteredAt ?? DateTime.utc(2026, 7, 28, 3, 35);

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
      schedulingMode: 'fixedDuration',
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
      otpEnteredAt: effectiveOtpEnteredAt,
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
    updatedAt: effectiveOtpEnteredAt,
  );
}

CanonicalBookingDocumentV3 _buildCompletedPendingReviewBooking({
  DateTime? completedAt,
  DateTime? reviewWindowEndsAt,
  CanonicalBookingStateV3 state =
      CanonicalBookingStateV3.completedPendingReview,
  bool reviewSubmitted = false,
  String disputeStatus = 'none',
  String disputeResolution = '',
  DateTime? disputeRaisedAt,
  DateTime? disputeResolvedAt,
  int customerRefundPaise = 0,
  int providerReleasePaise = 0,
  String payoutStatus = 'HELD',
  String payoutHoldReason = '',
}) {
  final inProgress = _buildInProgressBooking();
  final effectiveCompletedAt = completedAt ?? DateTime.utc(2026, 7, 28, 4, 30);
  final effectiveReviewWindowEndsAt =
      reviewWindowEndsAt ?? effectiveCompletedAt.add(const Duration(hours: 24));

  return CanonicalBookingDocumentV3(
    schemaVersion: inProgress.schemaVersion,
    bookingModelVersion: inProgress.bookingModelVersion,
    documentFormat: inProgress.documentFormat,
    bookingType: inProgress.bookingType,
    state: state,
    participants: inProgress.participants,
    service: inProgress.service,
    schedule: inProgress.schedule,
    lifecycle: CanonicalBookingLifecycleV3(
      requestedAt: inProgress.lifecycle.requestedAt,
      timerStartsAt: inProgress.lifecycle.timerStartsAt,
      wasQueuedOutsideWorkingHours:
          inProgress.lifecycle.wasQueuedOutsideWorkingHours,
      notifiedAt: inProgress.lifecycle.notifiedAt,
      acceptDeadlineAt: inProgress.lifecycle.acceptDeadlineAt,
      viewedByProviderAt: inProgress.lifecycle.viewedByProviderAt,
      respondedAt: inProgress.lifecycle.respondedAt,
      providerResponseType: inProgress.lifecycle.providerResponseType,
      responseSeconds: inProgress.lifecycle.responseSeconds,
      payDeadlineAt: inProgress.lifecycle.payDeadlineAt,
      paymentStartedAt: inProgress.lifecycle.paymentStartedAt,
      paidAt: inProgress.lifecycle.paidAt,
      paymentSeconds: inProgress.lifecycle.paymentSeconds,
      otpGeneratedAt: inProgress.lifecycle.otpGeneratedAt,
      otpEnteredAt: inProgress.lifecycle.otpEnteredAt,
      noShowAt: inProgress.lifecycle.noShowAt,
      serviceEndedAt: effectiveCompletedAt,
      disputeDeadlineAt: effectiveReviewWindowEndsAt,
      completedAt: effectiveCompletedAt,
      reviewWindowEndsAt: effectiveReviewWindowEndsAt,
      finalizedAt: null,
      cancelledAt: inProgress.lifecycle.cancelledAt,
    ),
    payment: inProgress.payment,
    financials: inProgress.financials,
    privacy: CanonicalBookingPrivacyV3(
      isPaidContactUnlocked: inProgress.privacy.isPaidContactUnlocked,
      contactUnlockedAt: inProgress.privacy.contactUnlockedAt,
      chatUnlockedAt: inProgress.privacy.chatUnlockedAt,
      otpVisibleToParent: false,
      exactAddressUnlocked: inProgress.privacy.exactAddressUnlocked,
      privacyVersion: inProgress.privacy.privacyVersion,
      privateParticipantsRefPath: inProgress.privacy.privateParticipantsRefPath,
    ),
    cancellation: inProgress.cancellation,
    dispute: CanonicalBookingDisputeV3(
      disputeId: disputeStatus == 'none' ? '' : 'booking-1',
      status: disputeStatus,
      raisedAt: disputeRaisedAt,
      raisedBy: disputeStatus == 'none' ? null : 'parent',
      reasonCode: disputeStatus == 'none' ? '' : 'SERVICE_QUALITY',
      description: disputeStatus == 'none'
          ? ''
          : 'The provider did not arrive at the booked time.',
      evidenceRefs: const <String>[],
      resolvedAt: disputeResolvedAt,
      resolvedBy: disputeResolvedAt == null ? null : 'admin',
      resolution: disputeResolution,
      resolutionVersion: disputeResolvedAt == null ? 0 : 1,
      financialAdjustmentId: disputeResolvedAt == null ? '' : 'adjustment-1',
      refundInstructionId:
          customerRefundPaise > 0 ? 'refund-instruction-1' : '',
      customerRefundPaise: customerRefundPaise,
      providerReleasePaise: providerReleasePaise,
    ),
    review: CanonicalBookingReviewV3(
      status: reviewSubmitted ? 'submitted' : '',
      reviewId: reviewSubmitted ? 'booking-1' : '',
      submittedAt: reviewSubmitted ? effectiveCompletedAt : null,
    ),
    payout: CanonicalBookingPayoutV3(
      status: payoutStatus,
      holdReason: payoutHoldReason,
      eligibleAt: effectiveReviewWindowEndsAt,
      readyAt: null,
      processingAt: null,
      releasedAt: null,
      failedAt: null,
      providerPayoutPaise: inProgress.financials!.providerPayoutPaise,
      priorPaidPaise: inProgress.payout.priorPaidPaise,
      remainingPayablePaise: inProgress.payout.remainingPayablePaise,
      payoutReference: inProgress.payout.payoutReference,
      externalTransactionId: inProgress.payout.externalTransactionId,
      failureCode: inProgress.payout.failureCode,
      retryCount: inProgress.payout.retryCount,
    ),
    statistics: inProgress.statistics,
    audit: const CanonicalBookingAuditV3(
      createdBy: BookingActorV3.system,
      lastUpdatedBy: BookingActorV3.provider,
      source: 'test',
    ),
    parentId: inProgress.parentId,
    providerId: inProgress.providerId,
    serviceId: inProgress.serviceId,
    stateQueryValue: state,
    bookingTypeQueryValue: inProgress.bookingTypeQueryValue,
    serviceAnchorAt: inProgress.serviceAnchorAt,
    scheduledStartAt: inProgress.scheduledStartAt,
    checkInDateTime: inProgress.checkInDateTime,
    acceptDeadlineAt: inProgress.acceptDeadlineAt,
    payDeadlineAt: inProgress.payDeadlineAt,
    completedAt: effectiveCompletedAt,
    customerId: inProgress.customerId,
    serviceOwnerId: inProgress.serviceOwnerId,
    createdAt: inProgress.createdAt,
    updatedAt: effectiveCompletedAt,
  );
}

extension on CanonicalBookingDocumentV3 {
  String get bookingIdForTest => 'booking-1';
}
