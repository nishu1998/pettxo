import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/message_model.dart';
import 'message_delivery_tick.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.timeLabel,
    this.showTick = false,
    this.isDelivered = false,
    this.isRead = false,
  });

  final MessageModel message;
  final bool isMine;
  final String timeLabel;
  final bool showTick;
  final bool isDelivered;
  final bool isRead;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine
        ? AppColors.primary
        : Colors.white.withValues(alpha: 0.98);
    final textColor = isMine ? Colors.white : AppColors.textDark;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.76,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isMine ? 20 : 6),
              bottomRight: Radius.circular(isMine ? 6 : 20),
            ),
            border: isMine
                ? null
                : Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.sourceServiceTitle.isNotEmpty) ...[
                Text(
                  message.sourceServiceTitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.82)
                        : AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                message.text,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeLabel,
                    style: TextStyle(
                      color: isMine
                          ? Colors.white.withValues(alpha: 0.82)
                          : AppColors.textGrey,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (showTick) ...[
                    const SizedBox(width: 8),
                    MessageDeliveryTick(
                      isDelivered: isDelivered,
                      isRead: isRead,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
