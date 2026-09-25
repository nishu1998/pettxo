import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/notifications/presentation/screens/notifications_screen.dart';

void main() {
  final now = DateTime(2026, 9, 25, 12);

  testWidgets(
    'booking title and timestamp share only the top row while body uses full width',
    (tester) async {
      await tester.pumpWidget(
        _cardApp(
          width: 360,
          card: NotificationCard(
            data: _bookingData(
              createdAt: now.subtract(const Duration(days: 1)),
            ),
            onTap: () {},
            now: now,
          ),
        ),
      );

      expect(find.text('1d'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);

      final titleWidth = tester
          .getSize(find.byKey(const Key('notification-title')))
          .width;
      final bodyWidth = tester
          .getSize(find.byKey(const Key('notification-body')))
          .width;
      expect(bodyWidth, greaterThan(titleWidth));
    },
  );

  testWidgets('read and unread cards retain their visual states', (
    tester,
  ) async {
    await tester.pumpWidget(
      _cardApp(
        card: Column(
          children: [
            NotificationCard(
              data: _bookingData(
                createdAt: now,
                read: false,
                title: 'Unread booking',
              ),
              onTap: () {},
              now: now,
            ),
            NotificationCard(
              data: _bookingData(
                createdAt: now,
                read: true,
                title: 'Read booking',
              ),
              onTap: () {},
              now: now,
            ),
          ],
        ),
      ),
    );

    final surfaces = tester
        .widgetList<Material>(
          find.byKey(const Key('notification-card-surface')),
        )
        .toList();
    expect(surfaces, hasLength(2));
    expect(surfaces[0].color, const Color(0xFFF7AF83));
    expect(surfaces[1].color, Colors.white);
  });

  testWidgets('relative and absolute notification dates remain unchanged', (
    tester,
  ) async {
    await tester.pumpWidget(
      _cardApp(
        card: Column(
          children: [
            NotificationCard(
              data: _bookingData(
                createdAt: now.subtract(const Duration(days: 3)),
                title: 'Recent update',
              ),
              onTap: () {},
              now: now,
            ),
            NotificationCard(
              data: _bookingData(
                createdAt: DateTime(2026, 9, 15),
                title: 'Older update',
              ),
              onTap: () {},
              now: now,
            ),
          ],
        ),
      ),
    );

    expect(find.text('3d'), findsOneWidget);
    expect(find.text('15/9/2026'), findsOneWidget);
  });

  testWidgets('long service and legacy copy render at large text scale', (
    tester,
  ) async {
    const legacyBody =
        'This legacy notification contains a deliberately long explanation '
        'that must continue wrapping safely without clipping or overflow.';
    await tester.pumpWidget(
      _cardApp(
        width: 320,
        textScaler: const TextScaler.linear(2),
        card: NotificationCard(
          data: _bookingData(
            createdAt: now,
            title:
                'Booking confirmed for an exceptionally long premium pet care service name',
            body: legacyBody,
          ),
          onTap: () {},
          now: now,
        ),
      ),
    );

    expect(find.text(legacyBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long social username uses avatar and omits redundant body', (
    tester,
  ) async {
    const title = 'Alexandria Montgomery-Wellington-Smith liked your post';
    await tester.pumpWidget(
      _cardApp(
        width: 320,
        card: NotificationCard(
          data: {
            'category': 'social',
            'type': 'socialLike',
            'title': title,
            'body': '',
            'senderId': '',
            'senderDisplayName': 'Alexandria Montgomery-Wellington-Smith',
            'senderPhotoUrl': '',
            'read': false,
            'isRead': false,
            'createdAt': Timestamp.fromDate(now),
          },
          onTap: () {},
          now: now,
        ),
      ),
    );

    expect(find.text(title), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byKey(const Key('notification-avatar')), findsOneWidget);
    expect(find.byKey(const Key('notification-body')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact social notification sizes naturally', (tester) async {
    await tester.pumpWidget(
      _cardApp(
        width: 360,
        card: NotificationCard(
          data: {
            'category': 'social',
            'type': 'socialLike',
            'title': 'Tanmay liked your post',
            'body': '',
            'senderId': '',
            'senderDisplayName': 'Tanmay',
            'senderPhotoUrl': '',
            'read': true,
            'isRead': true,
            'createdAt': Timestamp.fromDate(now),
          },
          onTap: () {},
          now: now,
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('notification-card-surface'))).height,
      lessThan(100),
    );
  });

  testWidgets('notification tap callback remains wired to the card', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _cardApp(
        card: NotificationCard(
          data: _bookingData(createdAt: now),
          onTap: () => tapped = true,
          now: now,
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(tapped, isTrue);
  });
}

Map<String, dynamic> _bookingData({
  required DateTime createdAt,
  bool read = false,
  String title = 'Booking confirmed',
  String body = 'Payment successful for Very Good Dog Walking.',
}) {
  return {
    'category': 'booking',
    'type': 'booking_confirmed',
    'title': title,
    'body': body,
    'read': read,
    'isRead': read,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

Widget _cardApp({
  required Widget card,
  double width = 400,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData().copyWith(textScaler: textScaler),
        child: SingleChildScrollView(
          child: Center(
            child: SizedBox(width: width, child: card),
          ),
        ),
      ),
    ),
  );
}
