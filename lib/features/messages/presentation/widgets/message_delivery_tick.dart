import 'package:flutter/material.dart';

class MessageDeliveryTick extends StatelessWidget {
  const MessageDeliveryTick({
    super.key,
    required this.isDelivered,
    required this.isRead,
  });

  final bool isDelivered;
  final bool isRead;

  @override
  Widget build(BuildContext context) {
    final color = isRead ? const Color(0xFF0C86FF) : Colors.white70;
    if (!isDelivered) {
      return Icon(Icons.done_rounded, size: 16, color: color);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(Icons.done_rounded, size: 16, color: color),
        Positioned(
          left: 4,
          child: Icon(Icons.done_rounded, size: 16, color: color),
        ),
      ],
    );
  }
}
