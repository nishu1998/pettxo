import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../../core/widgets/app_user_avatar.dart';
import '../../../bookings/domain/models/booking_flow_models.dart';
import '../../../bookings/presentation/navigation/booking_navigation_resolver.dart';
import '../../../messages/presentation/screens/chat_detail_screen.dart';
import '../../domain/notification_visibility.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../profile/presentation/widgets/profile_content_sections.dart';
import '../../../support/presentation/screens/support_ticket_detail_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static final BookingNavigationResolver _bookingNavigationResolver =
      BookingNavigationResolver();

  @visibleForTesting
  static BookingOpenRequest bookingOpenRequestFromNotificationData(
    Map<String, dynamic> data,
  ) {
    final bookingId = '${data['bookingId'] ?? data['data']?['bookingId'] ?? ''}'
        .trim();
    final role =
        '${data['recipientRole'] ?? data['data']?['recipientRole'] ?? ''}';
    return BookingNavigationResolver.openRequestForExternalBooking(
      bookingId: bookingId,
      contextMode: role == 'provider'
          ? BookingContextMode.delivering
          : BookingContextMode.receiving,
    );
  }

  @visibleForTesting
  static bool isVisibleInAppNotification(Map<String, dynamic> data) {
    return NotificationVisibility.isVisibleInApp(data);
  }

  @visibleForTesting
  static bool isPromotionalNotification(Map<String, dynamic> data) {
    final nested = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : const <String, dynamic>{};
    final category = '${data['category'] ?? nested['category'] ?? ''}'.trim();
    final type = '${data['type'] ?? nested['type'] ?? ''}'.trim();
    return category == 'promotion' || type == 'promotionalBroadcast';
  }

  @visibleForTesting
  static bool isActionableNotification(Map<String, dynamic> data) {
    return !isPromotionalNotification(data);
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _notificationsFor(String uid) {
    // Notifications are backend-created; the client only reads and marks them
    // read so lifecycle messages cannot be spoofed from the app.
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .limit(50)
        .snapshots();
  }

  bool _isUnreadNotification(Map<String, dynamic> data) {
    return data['read'] != true && data['isRead'] != true;
  }

  Future<void> _markAllNotificationsRead(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final unreadDocs = docs
        .where((doc) => _isUnreadNotification(doc.data()))
        .toList(growable: false);
    if (unreadDocs.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in unreadDocs) {
        batch.update(doc.reference, {
          'read': true,
          'isRead': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (_) {
      if (!context.mounted) return;
      AppSnackbar.warning(
        context,
        message: 'Unable to mark notifications as read right now.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: user == null
            ? const Column(
                children: [
                  _NotificationsHeader(unreadCount: 0),
                  Expanded(
                    child: _NotificationStateMessage(
                      title: 'Sign in required',
                      message: 'Sign in to see booking and social updates.',
                    ),
                  ),
                ],
              )
            : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _notificationsFor(user.uid),
                builder: (context, snapshot) {
                  final docs = _sortNotificationsByLatestFirst(
                    (snapshot.data?.docs ?? const [])
                        .where((doc) => isVisibleInAppNotification(doc.data()))
                        .toList(growable: false),
                  );
                  final unreadCount = docs
                      .where((doc) => _isUnreadNotification(doc.data()))
                      .length;

                  return Column(
                    children: [
                      _NotificationsHeader(
                        unreadCount: unreadCount,
                        onUnreadTap: unreadCount > 0
                            ? () => _markAllNotificationsRead(context, docs)
                            : null,
                      ),
                      Expanded(
                        child: () {
                          if (snapshot.hasError) {
                            return const _NotificationStateMessage(
                              title: 'Unable to load notifications',
                              message:
                                  'Please check your connection and try again.',
                            );
                          }
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            );
                          }
                          if (docs.isEmpty) {
                            return const _NotificationStateMessage(
                              title: 'You’re all caught up',
                              message:
                                  'Booking changes, follows, likes and comments will show up here.',
                            );
                          }

                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            children: docs
                                .map(
                                  (doc) => _NotificationTile(
                                    doc: doc,
                                    onTap: isActionableNotification(doc.data())
                                        ? () => _openNotification(context, doc)
                                        : null,
                                  ),
                                )
                                .toList(growable: false),
                          );
                        }(),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>>
  _sortNotificationsByLatestFirst(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> source,
  ) {
    final docs = source.toList(growable: false);
    docs.sort((a, b) => _sortDateFor(b).compareTo(_sortDateFor(a)));
    return docs;
  }

  DateTime _sortDateFor(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) return createdAt.toDate();
    final sentAt = data['sentAt'];
    if (sentAt is Timestamp) return sentAt.toDate();
    final updatedAt = data['updatedAt'];
    if (updatedAt is Timestamp) return updatedAt.toDate();
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _openNotification(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final isUnread = _isUnreadNotification(data);
    if (isUnread) {
      try {
        await doc.reference.update({
          'read': true,
          'isRead': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Navigation should still work even if the read-state write fails.
      }
    }

    if (!context.mounted) return;
    if (isPromotionalNotification(data)) {
      return;
    }
    final bookingRequest = bookingOpenRequestFromNotificationData(data);
    final bookingId = bookingRequest.bookingId;
    final category = '${data['category'] ?? data['data']?['category'] ?? ''}';
    final type = '${data['type'] ?? data['data']?['type'] ?? ''}';
    final chatId = '${data['chatId'] ?? data['data']?['chatId'] ?? ''}'.trim();
    final senderId = '${data['senderId'] ?? data['data']?['senderId'] ?? ''}';
    final recipientId =
        '${data['userId'] ?? data['recipientId'] ?? data['data']?['recipientId'] ?? ''}';
    final postId = '${data['postId'] ?? data['data']?['postId'] ?? ''}';
    final ticketId = '${data['ticketId'] ?? data['data']?['ticketId'] ?? ''}'
        .trim();
    if ((type == 'chat' || type == 'chatMessage' || category == 'chat') &&
        chatId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatDetailScreen(chatId: chatId)),
      );
      return;
    }
    if ((category == 'support' || type == 'supportReply') &&
        ticketId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SupportTicketDetailScreen(ticketId: ticketId),
        ),
      );
      return;
    }
    if (bookingId.isEmpty) {
      if (category == 'social') {
        String profileUserId = '';
        if (type == 'socialFollow') {
          profileUserId = senderId.trim();
        } else if (type == 'socialLike' || type == 'socialComment') {
          profileUserId = recipientId.trim();
        }

        if (profileUserId.isEmpty) {
          Navigator.pushNamed(context, '/home');
          AppSnackbar.warning(context, message: 'Profile unavailable.');
          return;
        }

        if ((type == 'socialLike' || type == 'socialComment') &&
            postId.trim().isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfilePostDetailScreen.fromPostId(
                authorId: profileUserId,
                initialPostId: postId.trim(),
                currentUserId: FirebaseAuth.instance.currentUser?.uid ?? '',
              ),
            ),
          );
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ProfileScreen(userId: profileUserId),
          ),
        );
      }
      return;
    }

    await _bookingNavigationResolver.openBookingRequest(
      context,
      bookingRequest,
    );
  }
}

class _NotificationsHeader extends StatelessWidget {
  final int unreadCount;
  final VoidCallback? onUnreadTap;

  const _NotificationsHeader({required this.unreadCount, this.onUnreadTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 6),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.07),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textDark,
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            'Notifications',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const Spacer(),
          if (unreadCount > 0) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onUnreadTap,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Text(
                    '$unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback? onTap;

  const _NotificationTile({required this.doc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = '${data['title'] ?? 'Pettxo update'}';
    final body = '${data['body'] ?? ''}';
    final type = '${data['type'] ?? ''}';
    final category = '${data['category'] ?? ''}';
    final isUnread = data['read'] != true && data['isRead'] != true;
    final createdAt = data['createdAt'];
    final createdDate = createdAt is Timestamp ? createdAt.toDate() : null;
    final senderId = '${data['senderId'] ?? data['data']?['senderId'] ?? ''}';
    final senderDisplayName =
        '${data['senderDisplayName'] ?? data['data']?['senderDisplayName'] ?? ''}';
    final senderPhotoUrl =
        '${data['senderPhotoUrl'] ?? data['data']?['senderPhotoUrl'] ?? ''}';
    final isActionable = onTap != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isUnread ? 0.08 : 0.045),
              blurRadius: isUnread ? 24 : 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: isUnread ? const Color(0xFFF7AF83) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            canRequestFocus: isActionable,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
              decoration: BoxDecoration(
                color: isUnread ? const Color(0xFFF7AF83) : Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: AppColors.textGrey.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _avatarContent(
                    senderId: senderId,
                    senderDisplayName: senderDisplayName,
                    senderPhotoUrl: senderPhotoUrl,
                    type: type,
                    category: category,
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: _buildStyledText(title, body)),
                  const SizedBox(width: 12),
                  Text(
                    _relativeTime(createdDate),
                    style: const TextStyle(
                      color: AppColors.textGrey,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarContent({
    required String senderId,
    required String senderDisplayName,
    required String senderPhotoUrl,
    required String type,
    required String category,
  }) {
    if (category == 'social') {
      return _SocialNotificationAvatar(
        senderId: senderId,
        senderDisplayName: senderDisplayName,
        fallbackPhotoUrl: senderPhotoUrl,
        badgeColor: _badgeColorFor(type, category),
        badgeIcon: _iconFor(type, category),
      );
    }

    return Container(
      width: 52,
      height: 52,
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      child: Icon(_iconFor(type, category), color: AppColors.primary),
    );
  }

  Color _badgeColorFor(String type, String category) {
    if (category == 'social') {
      if (type == 'socialFollow') return const Color(0xFF2FA56A);
      if (type == 'socialComment') return const Color(0xFF4A78D1);
      if (type == 'socialLike') return AppColors.primary;
    }
    return AppColors.primary;
  }

  IconData _iconFor(String type, String category) {
    if (category == 'chat' || type == 'chat' || type == 'chatMessage') {
      return Icons.chat_bubble_outline_rounded;
    }
    if (category == 'social') {
      if (type == 'socialFollow') return Icons.person_add_alt_1_rounded;
      if (type == 'socialLike') return Icons.favorite_rounded;
      if (type == 'socialComment') return Icons.mode_comment_rounded;
      return Icons.notifications_none_rounded;
    }
    if (category == 'support' || type == 'supportReply') {
      return Icons.support_agent_rounded;
    }
    if (category == 'promotion' || type == 'promotionalBroadcast') {
      return Icons.campaign_rounded;
    }
    if (type.contains('Otp')) return Icons.password_rounded;
    if (type.contains('Accepted')) return Icons.verified_rounded;
    if (type.contains('Rejected') || type.contains('Cancelled')) {
      return Icons.event_busy_rounded;
    }
    if (type.contains('Started')) return Icons.play_circle_outline_rounded;
    if (type.contains('Completed')) return Icons.check_circle_outline_rounded;
    return Icons.calendar_today_outlined;
  }

  Widget _buildStyledText(String title, String body) {
    final cleanedTitle = title.trim();
    final cleanedBody = body.trim();
    final combined = cleanedTitle.isEmpty ? 'Pettxo update' : cleanedTitle;
    final subjectLength = _subjectLengthFor(combined);
    final safeSubjectLength = subjectLength.clamp(0, combined.length);
    final subject = combined.substring(0, safeSubjectLength).trim();
    final remainder = combined.substring(safeSubjectLength).trimLeft();
    final bodySuffix = _shouldHideBody(cleanedBody) ? '' : cleanedBody;

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: subject,
            style: const TextStyle(
              fontSize: 16,
              color: AppColors.textDark,
              fontWeight: FontWeight.w800,
              height: 1.45,
            ),
          ),
          if (remainder.isNotEmpty)
            TextSpan(
              text: ' $remainder',
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textDark,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            ),
          if (bodySuffix.isNotEmpty)
            TextSpan(
              text: ' $bodySuffix',
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textDark,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            ),
        ],
      ),
    );
  }

  int _subjectLengthFor(String title) {
    const actionMarkers = <String>[
      ' liked',
      ' followed',
      ' commented',
      ' started',
      ' replied',
      ' requested',
      ' accepted',
      ' rejected',
      ' cancelled',
      ' completed',
      ' sent',
      ' mentioned',
    ];

    var splitIndex = title.length;
    for (final marker in actionMarkers) {
      final index = title.indexOf(marker);
      if (index > 0 && index < splitIndex) {
        splitIndex = index;
      }
    }
    return splitIndex;
  }

  bool _shouldHideBody(String body) {
    if (body.isEmpty) return true;
    final normalized = body.toLowerCase();
    return normalized.startsWith('tap to view') ||
        normalized.startsWith('tap to see') ||
        normalized.startsWith('see what they are sharing') ||
        normalized.startsWith('see what they’re sharing') ||
        normalized.startsWith("see what they're sharing");
  }

  String _relativeTime(DateTime? date) {
    if (date == null) return 'Just now';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _SocialNotificationAvatar extends StatelessWidget {
  final String senderId;
  final String senderDisplayName;
  final String fallbackPhotoUrl;
  final Color badgeColor;
  final IconData badgeIcon;

  const _SocialNotificationAvatar({
    required this.senderId,
    required this.senderDisplayName,
    required this.fallbackPhotoUrl,
    required this.badgeColor,
    required this.badgeIcon,
  });

  @override
  Widget build(BuildContext context) {
    if (senderId.trim().isEmpty) {
      return _buildAvatarStack(fallbackPhotoUrl.trim());
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(senderId.trim())
          .snapshots(),
      builder: (context, snapshot) {
        final livePhotoUrl = '${snapshot.data?.data()?['profileImage'] ?? ''}'
            .trim();
        final resolvedPhotoUrl = livePhotoUrl.isNotEmpty
            ? livePhotoUrl
            : fallbackPhotoUrl.trim();
        return _buildAvatarStack(resolvedPhotoUrl);
      },
    );
  }

  Widget _buildAvatarStack(String photoUrl) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppUserAvatar(
            size: 52,
            imageUrl: photoUrl,
            fallback: _fallbackAvatar(),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(badgeIcon, size: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackAvatar() {
    return AppUserAvatarFallback(
      initials: _initialsFromName(senderDisplayName),
      backgroundColor: AppColors.background,
      textStyle: const TextStyle(
        color: AppColors.textDark,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  String _initialsFromName(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _NotificationStateMessage extends StatelessWidget {
  final String title;
  final String message;

  const _NotificationStateMessage({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFFFFF2EA),
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
