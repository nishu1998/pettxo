import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/messages/domain/models/message_model.dart';
import 'package:pettexo/features/messages/presentation/widgets/chat_bubble.dart';

MessageModel message(Map<String, dynamic> data) =>
    MessageModel.fromMap('message-1', data);

void main() {
  testWidgets('renders image content with timestamp and delivery tick', (
    tester,
  ) async {
    final image = message({
      'type': 'image',
      'senderId': 'uid-a',
      'receiverId': 'uid-b',
      'storagePath': 'chatMedia/chat_uid-a_uid-b/message-1/image.jpg',
      'imageWidth': 1200,
      'imageHeight': 800,
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            message: image,
            isMine: true,
            timeLabel: '7:30 PM',
            showTick: true,
            isDelivered: true,
            isRead: true,
            imageBuilder: (_, _) => const ColoredBox(
              key: ValueKey('private-image'),
              color: Colors.orange,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('private-image')), findsOneWidget);
    expect(find.text('7:30 PM'), findsOneWidget);
    expect(find.byIcon(Icons.done_rounded), findsNWidgets(2));
  });

  testWidgets('unknown types render a safe placeholder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            message: message({'type': 'future-media'}),
            isMine: false,
            timeLabel: 'Now',
          ),
        ),
      ),
    );
    expect(find.text('Unsupported message'), findsOneWidget);
  });

  testWidgets('text rendering remains unchanged', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            message: message({'text': 'Hello'}),
            isMine: false,
            timeLabel: 'Now',
          ),
        ),
      ),
    );
    expect(find.text('Hello'), findsOneWidget);
  });
}
