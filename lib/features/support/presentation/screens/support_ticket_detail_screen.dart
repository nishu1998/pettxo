import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/support_repository.dart';
import '../../domain/models/support_models.dart';
import '../widgets/support_widgets.dart';

class SupportTicketDetailScreen extends StatefulWidget {
  const SupportTicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  State<SupportTicketDetailScreen> createState() =>
      _SupportTicketDetailScreenState();
}

class _SupportTicketDetailScreenState extends State<SupportTicketDetailScreen> {
  final SupportRepository _repository = SupportRepository();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<SupportTicketMessage> _olderMessages = <SupportTicketMessage>[];
  final Set<String> _olderMessageIds = <String>{};

  DocumentSnapshot<Map<String, dynamic>>? _paginationCursor;
  bool _isLoadingOlder = false;
  bool _hasMoreOlder = true;
  bool _isSending = false;
  bool _isMarkingRead = false;
  bool _didInitialScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
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
    if (_scrollController.position.pixels <= 240) {
      unawaited(_loadOlderMessages());
    }
  }

  Future<void> _loadOlderMessages() async {
    final cursor = _paginationCursor;
    if (cursor == null || _isLoadingOlder || !_hasMoreOlder) return;

    setState(() => _isLoadingOlder = true);
    try {
      final page = await _repository.fetchOlderMessages(
        widget.ticketId,
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
      AppSnackbar.showWarning(context, 'Unable to load older replies.');
    } finally {
      if (mounted) {
        setState(() => _isLoadingOlder = false);
      }
    }
  }

  Future<void> _markReadIfNeeded(SupportTicket? ticket) async {
    if (ticket == null ||
        ticket.customerUnreadCount <= 0 ||
        _isMarkingRead ||
        _repository.currentUid.isEmpty) {
      return;
    }
    _isMarkingRead = true;
    try {
      await _repository.markTicketRead(ticket.ticketId);
    } catch (_) {
      // Best-effort unread reset should not block the conversation screen.
    } finally {
      _isMarkingRead = false;
    }
  }

  Future<void> _sendReply() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isSending) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSending = true);
    try {
      await _repository.replyToTicket(
        ticketId: widget.ticketId,
        message: message,
      );
      _messageController.clear();
    } catch (error) {
      if (!mounted) return;
      AppSnackbar.showError(context, _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SupportTicket?>(
      stream: _repository.watchTicket(widget.ticketId),
      builder: (context, ticketSnapshot) {
        final ticket = ticketSnapshot.data;
        if (ticket != null && ticket.customerUnreadCount > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_markReadIfNeeded(ticket));
          });
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.textDark,
            elevation: 0,
            titleSpacing: 0,
            title: ticket == null
                ? const Text('Support ticket')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ticket.subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${ticket.category.label} • ${ticket.ticketId}',
                        style: const TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
            actions: [
              if (ticket != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: SupportStatusChip(status: ticket.status),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              if (ticketSnapshot.hasError)
                const Expanded(
                  child: SupportStatePane(
                    icon: Icons.support_agent_outlined,
                    title: 'Conversation unavailable',
                    message:
                        'We could not load this support conversation right now.',
                  ),
                )
              else if (ticket == null &&
                  ticketSnapshot.connectionState == ConnectionState.waiting)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (ticket == null)
                const Expanded(
                  child: SupportStatePane(
                    icon: Icons.support_outlined,
                    title: 'Ticket not found',
                    message:
                        'This support ticket is no longer available in your account.',
                  ),
                )
              else
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _repository.watchRecentMessageSnapshots(
                      widget.ticketId,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const SupportStatePane(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'Replies are unavailable',
                          message:
                              'We could not load this conversation right now.',
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          (snapshot.data?.docs.isEmpty ?? true)) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        );
                      }

                      final liveMessages = (snapshot.data?.docs ?? const [])
                          .map(SupportTicketMessage.fromDocument)
                          .toList(growable: false);
                      final mergedMessages = <SupportTicketMessage>[
                        ...liveMessages,
                        ..._olderMessages.where(
                          (older) =>
                              !liveMessages.any((live) => live.id == older.id),
                        ),
                      ];
                      final orderedMessages = mergedMessages.reversed.toList(
                        growable: false,
                      );

                      if ((snapshot.data?.docs.isNotEmpty ?? false) &&
                          _paginationCursor == null) {
                        _paginationCursor = snapshot.data!.docs.last;
                        _hasMoreOlder = snapshot.data!.docs.length >= 40;
                      }

                      _maybeKeepScrollNearBottom(orderedMessages.length);

                      return Column(
                        children: [
                          Expanded(
                            child: CustomScrollView(
                              controller: _scrollController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              slivers: [
                                SliverToBoxAdapter(
                                  child: _buildTicketDetailsCard(ticket),
                                ),
                                if (_isLoadingOlder)
                                  const SliverToBoxAdapter(
                                    child: Padding(
                                      padding: EdgeInsets.fromLTRB(
                                        16,
                                        12,
                                        16,
                                        0,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (orderedMessages.isEmpty)
                                  const SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: SupportStatePane(
                                      icon: Icons.forum_outlined,
                                      title: 'No replies yet',
                                      message:
                                          'Your ticket is created. Replies from Pettxo support will appear here.',
                                    ),
                                  )
                                else
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      18,
                                      16,
                                      18,
                                    ),
                                    sliver: SliverList.separated(
                                      itemCount: orderedMessages.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: 14),
                                      itemBuilder: (context, index) {
                                        final message = orderedMessages[index];
                                        final isCustomer =
                                            message.senderType ==
                                            SupportMessageSenderType.customer;
                                        return Align(
                                          alignment: isCustomer
                                              ? Alignment.centerRight
                                              : Alignment.centerLeft,
                                          child: SupportMessageBubble(
                                            message: message,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          _buildReplyComposer(ticket),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('unauthenticated')) {
      return 'Please sign in again and try once more.';
    }
    if (message.contains('permission-denied')) {
      return 'This ticket is no longer available to your account.';
    }
    return 'We could not send your reply right now.';
  }

  Widget _buildTicketDetailsCard(SupportTicket ticket) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ticket.status == SupportTicketStatus.resolved
                      ? 'This ticket is resolved. You can still review the conversation below.'
                      : 'Pettxo support will reply here when an authorized team member responds.',
                  style: const TextStyle(
                    color: AppColors.textGrey,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Initial issue',
            style: TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            ticket.initialMessage,
            style: const TextStyle(
              color: AppColors.textGrey,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _InfoChip(icon: Icons.call_outlined, label: ticket.contactNumber),
              _InfoChip(
                icon: Icons.schedule_outlined,
                label: _dateLabel(ticket.createdAt),
              ),
            ],
          ),
          if (ticket.attachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Attachments',
              style: TextStyle(
                color: AppColors.textDark,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: ticket.attachments
                  .map(
                    (attachment) => _AttachmentThumb(
                      attachment: attachment,
                      repository: _repository,
                      onTap: () => _openAttachmentPreview(attachment),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReplyComposer(SupportTicket ticket) {
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    final safeAreaBottom = MediaQuery.paddingOf(context).bottom;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        viewInsetsBottom > 0 ? viewInsetsBottom + 12 : safeAreaBottom + 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              enabled: ticket.status != SupportTicketStatus.resolved,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: ticket.status == SupportTicketStatus.resolved
                    ? 'This ticket is resolved'
                    : 'Reply to support',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed:
                _isSending || ticket.status == SupportTicketStatus.resolved
                ? null
                : _sendReply,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(54, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: _isSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }

  void _maybeKeepScrollNearBottom(int messageCount) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final shouldStickToBottom = !_didInitialScrollToBottom || _isNearBottom();
      if (shouldStickToBottom) {
        _scrollToBottom(jump: !_didInitialScrollToBottom);
        _didInitialScrollToBottom = true;
      }
    });
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final maxExtent = _scrollController.position.maxScrollExtent;
    return maxExtent - _scrollController.position.pixels <= 180;
  }

  void _scrollToBottom({bool jump = false}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (jump) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openAttachmentPreview(
    SupportTicketAttachment attachment,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(20),
          backgroundColor: Colors.black,
          child: AspectRatio(
            aspectRatio: 1,
            child: FutureBuilder<String>(
              future: _repository.getAttachmentDownloadUrl(
                attachment.storagePath,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Unable to open this attachment right now.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: InteractiveViewer(
                        child: Image.network(
                          snapshot.data!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _dateLabel(DateTime? date) {
    if (date == null) return 'Submitted just now';
    return 'Submitted ${date.day}/${date.month}/${date.year}';
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
    required this.attachment,
    required this.repository,
    required this.onTap,
  });

  final SupportTicketAttachment attachment;
  final SupportRepository repository;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 88,
          height: 88,
          color: Colors.white,
          child: FutureBuilder<String>(
            future: repository.getAttachmentDownloadUrl(attachment.storagePath),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                );
              }
              return Image.network(snapshot.data!, fit: BoxFit.cover);
            },
          ),
        ),
      ),
    );
  }
}
