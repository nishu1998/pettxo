import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/models/chat_model.dart';
import '../../domain/models/message_model.dart';
import '../widgets/chat_bubble.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key, required this.chatId});

  final String chatId;

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final ChatRepository _repository = ChatRepository();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<MessageModel> _olderMessages = <MessageModel>[];
  final Set<String> _olderMessageIds = <String>{};
  DocumentSnapshot<Map<String, dynamic>>? _paginationCursor;
  bool _isLoadingOlder = false;
  bool _hasMoreOlder = true;
  bool _isSending = false;

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    unawaited(_markDeliveredAndRead());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoadingOlder || !_hasMoreOlder) {
      return;
    }

    final threshold = _scrollController.position.maxScrollExtent - 240;
    if (_scrollController.position.pixels >= threshold) {
      unawaited(_loadOlderMessages());
    }
  }

  Future<void> _loadOlderMessages() async {
    final cursor = _paginationCursor;
    if (cursor == null || _isLoadingOlder || !_hasMoreOlder) return;

    setState(() => _isLoadingOlder = true);
    try {
      final page = await _repository.fetchOlderMessages(
        widget.chatId,
        startAfter: cursor,
      );
      for (final message in page.messages) {
        if (_olderMessageIds.add(message.id)) {
          _olderMessages.add(message);
        }
      }
      _paginationCursor = page.cursor;
      _hasMoreOlder = page.hasMore && page.cursor != null;
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Unable to load older messages.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingOlder = false);
      }
    }
  }

  Future<void> _markDeliveredAndRead() async {
    if (_currentUid.isEmpty) return;
    try {
      await _repository.markChatDelivered(chatId: widget.chatId);
      await _repository.markChatRead(chatId: widget.chatId);
    } catch (_) {
      // Best-effort acknowledgement should not block the screen.
    }
  }

  Future<void> _sendMessage(ChatModel? chat) async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending || chat == null || chat.isClosed) return;

    setState(() => _isSending = true);
    try {
      await _repository.sendChatMessage(
        chatId: widget.chatId,
        text: text,
        sourceServiceId: chat.lastServiceId.isEmpty ? null : chat.lastServiceId,
      );
      _messageController.clear();
      unawaited(_markDeliveredAndRead());
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: _humanizeError(error),
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ChatModel?>(
      stream: _repository.watchChat(widget.chatId),
      builder: (context, chatSnapshot) {
        final chat = chatSnapshot.data;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.textDark,
            elevation: 0,
            titleSpacing: 0,
            title: chat == null
                ? const Text('Chat')
                : Row(
                    children: [
                      _HeaderAvatar(
                        name: chat.otherParticipantNameFor(_currentUid),
                        photoUrl: chat.otherParticipantPhotoUrlFor(_currentUid),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              chat.otherParticipantNameFor(_currentUid),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                              ),
                            ),
                            if (chat.lastServiceTitle.isNotEmpty)
                              Text(
                                chat.lastServiceTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textGrey,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          body: Column(
            children: [
              if (chatSnapshot.hasError)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Unable to load this chat right now.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else if (chat == null)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      if (chat.isClosed)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF4EE),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.16),
                            ),
                          ),
                          child: const Text(
                            'This conversation is closed. New messages are disabled.',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      Expanded(
                        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _repository.watchRecentMessageSnapshots(
                            widget.chatId,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Unable to load messages right now.',
                                    style: TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }

                            final docs = snapshot.data?.docs ?? const [];
                            final latestMessages = docs
                                .map(MessageModel.fromDocument)
                                .toList(growable: false);
                            if (docs.isNotEmpty && _olderMessages.isEmpty) {
                              _paginationCursor = docs.last;
                            }
                            if (docs.length < 30) {
                              _hasMoreOlder = false;
                            }
                            if (latestMessages.isNotEmpty) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                unawaited(_markDeliveredAndRead());
                              });
                            }

                            final messages = _mergeMessages(
                              latestMessages,
                              _olderMessages,
                            );

                            if (messages.isEmpty && !snapshot.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                ),
                              );
                            }

                            if (messages.isEmpty) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'No messages yet. Say hello to get started.',
                                    style: TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }

                            return ListView.builder(
                              controller: _scrollController,
                              reverse: true,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                10,
                                16,
                                16,
                              ),
                              itemCount: messages.length + 1,
                              itemBuilder: (context, index) {
                                if (index == messages.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Center(
                                      child: _isLoadingOlder
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: AppColors.primary,
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  );
                                }

                                final message = messages[index];
                                final isMine = message.isSentBy(_currentUid);
                                final isDelivered = message.deliveredTo
                                    .contains(message.receiverId);
                                final isRead = message.readBy.contains(
                                  message.receiverId,
                                );

                                return ChatBubble(
                                  message: message,
                                  isMine: isMine,
                                  timeLabel: _formatTime(message.createdAt),
                                  showTick: isMine,
                                  isDelivered: isDelivered,
                                  isRead: isRead,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    border: Border(
                      top: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          enabled: !_isSending && !(chat?.isClosed ?? false),
                          decoration: InputDecoration(
                            hintText: 'Type a message',
                            filled: true,
                            fillColor: const Color(0xFFF8F2ED),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(chat),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 52,
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _isSending || (chat?.isClosed ?? false)
                                ? AppColors.primary.withValues(alpha: 0.45)
                                : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            onPressed: _isSending || (chat?.isClosed ?? false)
                                ? null
                                : () => _sendMessage(chat),
                            icon: _isSending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.send_rounded,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<MessageModel> _mergeMessages(
    List<MessageModel> latestMessages,
    List<MessageModel> olderMessages,
  ) {
    final ids = <String>{};
    final merged = <MessageModel>[];
    for (final message in [...latestMessages, ...olderMessages]) {
      if (ids.add(message.id)) {
        merged.add(message);
      }
    }
    return merged;
  }

  String _formatTime(DateTime? date) {
    if (date == null) return 'Now';
    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  String _humanizeError(Object error) {
    final message = error.toString();
    if (message.contains('Message text is too long')) {
      return 'Messages can be up to 1000 characters.';
    }
    if (message.contains('Message text is required')) {
      return 'Please enter a message.';
    }
    if (message.contains('closed')) {
      return 'This conversation is closed.';
    }
    return 'Unable to send your message right now.';
  }
}

class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({required this.name, required this.photoUrl});

  final String name;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? 'P'
        : name.trim().substring(0, 1).toUpperCase();

    if (photoUrl.isNotEmpty) {
      return CircleAvatar(radius: 20, backgroundImage: NetworkImage(photoUrl));
    }

    return CircleAvatar(
      radius: 20,
      backgroundColor: const Color(0xFFF4EFEA),
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.textDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
