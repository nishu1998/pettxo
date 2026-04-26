import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../bookings/domain/models/booking_flow_models.dart';
import '../../../bookings/presentation/screens/booking_detail_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  Stream<QuerySnapshot<Map<String, dynamic>>> _notificationsFor(String uid) {
    // Notifications are backend-created; the client only reads and marks them
    // read so lifecycle messages cannot be spoofed from the app.
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: uid)
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: -50,
              right: -35,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.06),
                ),
              ),
            ),
            Column(
              children: [
                const _NotificationsHeader(),
                Expanded(
                  child: user == null
                      ? const _NotificationStateMessage(
                          title: 'Sign in required',
                          message:
                              'Sign in to see booking updates, reminders and alerts.',
                        )
                      : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: _notificationsFor(user.uid),
                          builder: (context, snapshot) {
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

                            final docs = [...snapshot.data?.docs ?? []];
                            docs.sort((a, b) {
                              final aTime = a.data()['createdAt'];
                              final bTime = b.data()['createdAt'];
                              final aDate = aTime is Timestamp
                                  ? aTime.toDate()
                                  : DateTime.fromMillisecondsSinceEpoch(0);
                              final bDate = bTime is Timestamp
                                  ? bTime.toDate()
                                  : DateTime.fromMillisecondsSinceEpoch(0);
                              return bDate.compareTo(aDate);
                            });

                            if (docs.isEmpty) {
                              return const _NotificationStateMessage(
                                title: 'You’re all caught up',
                                message:
                                    'Recent booking changes, OTP updates and completion alerts will show up here.',
                              );
                            }

                            final unreadCount = docs.where((doc) {
                              final data = doc.data();
                              return data['read'] != true &&
                                  data['isRead'] != true;
                            }).length;

                            return ListView(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                              children: [
                                _CaughtUpCard(unreadCount: unreadCount),
                                const SizedBox(height: 18),
                                ...docs.map(
                                  (doc) => _NotificationTile(
                                    doc: doc,
                                    onTap: () =>
                                        _openNotification(context, doc),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openNotification(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    await doc.reference.update({
      'read': true,
      'isRead': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!context.mounted) return;
    final bookingId =
        '${data['bookingId'] ?? data['data']?['bookingId'] ?? ''}';
    if (bookingId.isEmpty) return;

    final role =
        '${data['recipientRole'] ?? data['data']?['recipientRole'] ?? ''}';
    final contextMode = role == 'provider'
        ? BookingContextMode.delivering
        : BookingContextMode.receiving;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BookingDetailScreen(bookingId: bookingId, contextMode: contextMode),
      ),
    );
  }
}

class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.notifications_active_outlined,
              color: AppColors.primary,
              size: 24,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Notifications',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaughtUpCard extends StatelessWidget {
  final int unreadCount;

  const _CaughtUpCard({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.08),
            Colors.white.withValues(alpha: 0.96),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Booking updates',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Requests, confirmations, OTP updates and completion alerts stay in sync here.',
                  style: TextStyle(
                    color: AppColors.textGrey,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Text(
              '$unreadCount',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final VoidCallback onTap;

  const _NotificationTile({required this.doc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = '${data['title'] ?? 'Pettxo update'}';
    final body = '${data['body'] ?? ''}';
    final type = '${data['type'] ?? ''}';
    final isUnread = data['read'] != true && data['isRead'] != true;
    final createdAt = data['createdAt'];
    final createdDate = createdAt is Timestamp ? createdAt.toDate() : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isUnread
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : AppColors.primary.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: isUnread
                    ? const Color(0xFFFFF2EA)
                    : AppColors.background,
                child: Icon(_iconFor(type), color: AppColors.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textGrey,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _relativeTime(createdDate),
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) ...[
                const SizedBox(width: 12),
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String type) {
    if (type.contains('Otp')) return Icons.password_rounded;
    if (type.contains('Accepted')) return Icons.verified_rounded;
    if (type.contains('Rejected') || type.contains('Cancelled')) {
      return Icons.event_busy_rounded;
    }
    if (type.contains('Started')) return Icons.play_circle_outline_rounded;
    if (type.contains('Completed')) return Icons.check_circle_outline_rounded;
    return Icons.calendar_today_outlined;
  }

  String _relativeTime(DateTime? date) {
    if (date == null) return 'Just now';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return '${date.day}/${date.month}/${date.year}';
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
