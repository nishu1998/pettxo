import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/message_model.dart';
import 'message_delivery_tick.dart';
import 'private_chat_image.dart';

class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.timeLabel,
    this.showTick = false,
    this.isDelivered = false,
    this.isRead = false,
    this.imageBuilder,
  });

  final MessageModel message;
  final bool isMine;
  final String timeLabel;
  final bool showTick;
  final bool isDelivered;
  final bool isRead;
  final Widget Function(BuildContext context, MessageModel message)?
  imageBuilder;

  @override
  Widget build(BuildContext context) {
    final bubbleColor = isMine
        ? AppColors.primary
        : Colors.white.withValues(alpha: 0.98);
    final textColor = isMine ? Colors.white : AppColors.textDark;

    final content = message.isText
        ? Text(
            message.text,
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          )
        : message.isImage
        ? _ImageMessageContent(message: message, imageBuilder: imageBuilder)
        : Text(
            'Unsupported message',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.82),
              fontSize: 14,
              fontStyle: FontStyle.italic,
            ),
          );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.76,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: message.isImage
              ? const EdgeInsets.fromLTRB(5, 5, 8, 8)
              : const EdgeInsets.fromLTRB(14, 12, 14, 10),
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
              content,
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

class _ImageMessageContent extends StatelessWidget {
  const _ImageMessageContent({required this.message, this.imageBuilder});

  final MessageModel message;
  final Widget Function(BuildContext context, MessageModel message)?
  imageBuilder;

  @override
  Widget build(BuildContext context) {
    final ratio = message.imageWidth / message.imageHeight;
    final width = (MediaQuery.sizeOf(context).width * 0.68).clamp(180.0, 280.0);
    final height = (width / ratio).clamp(120.0, 320.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: width,
        height: height,
        child:
            imageBuilder?.call(context, message) ??
            PrivateChatImage(
              storagePath: message.storagePath,
              aspectRatio: ratio,
            ),
      ),
    );
  }
}
