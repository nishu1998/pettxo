import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/models/chat_model.dart';
import 'chat_detail_screen.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final repository = ChatRepository();
    debugPrint(
      'Messages tab debug -> currentUserId=$currentUid, '
      'query=chats.where(participantIds, arrayContains: $currentUid).orderBy(lastMessageAt desc).limit(40)',
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                        letterSpacing: -0.4,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Talk with providers and customers in one place.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: currentUid.isEmpty
                  ? const _MessagesStateMessage(
                      title: 'Sign in to view messages',
                      message:
                          'Your conversations will appear here once you are signed in.',
                    )
                  : StreamBuilder<List<ChatModel>>(
                      stream: repository.watchChatsFor(currentUid),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          debugPrint(
                            'Messages tab debug -> stream exception=${snapshot.error}',
                          );
                          return const _MessagesStateMessage(
                            title: 'Unable to load messages',
                            message: 'Please try again in a moment.',
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          );
                        }

                        final chats = snapshot.data!;
                        if (chats.isEmpty) {
                          return const _MessagesStateMessage(
                            title: 'No conversations yet',
                            message:
                                'Tap "Message Provider" on a service to start chatting.',
                          );
                        }

                        return ListView.separated(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            10,
                            20,
                            SocialBottomNav.contentBottomPadding(context),
                          ),
                          itemCount: chats.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final chat = chats[index];
                            final otherName = chat.otherParticipantNameFor(
                              currentUid,
                            );
                            final unreadCount = chat.unreadCountFor(currentUid);

                            return InkWell(
                              borderRadius: BorderRadius.circular(22),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ChatDetailScreen(chatId: chat.id),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.94),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: AppColors.textGrey.withValues(
                                      alpha: 0.16,
                                    ),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.03,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    _ChatAvatar(
                                      name: otherName,
                                      photoUrl: chat
                                          .otherParticipantPhotoUrlFor(
                                            currentUid,
                                          ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  otherName,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: AppColors.textDark,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                _relativeTime(
                                                  chat.lastMessageAt,
                                                ),
                                                style: const TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.textGrey,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          if (chat.lastServiceTitle.isNotEmpty)
                                            Text(
                                              chat.lastServiceTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          if (chat.lastServiceTitle.isNotEmpty)
                                            const SizedBox(height: 4),
                                          Text(
                                            chat.lastMessage.isEmpty
                                                ? 'Start the conversation'
                                                : chat.lastMessage,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              height: 1.4,
                                              color: AppColors.textGrey,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (unreadCount > 0) ...[
                                      const SizedBox(width: 12),
                                      Container(
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                          minHeight: 28,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(
                                          color: AppColors.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          unreadCount > 99
                                              ? '99+'
                                              : '$unreadCount',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SocialBottomNav(
        activeTab: SocialAppTab.messages,
      ),
    );
  }

  static String _relativeTime(DateTime? date) {
    if (date == null) return 'Now';
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min';
    if (diff.inHours < 24) return '${diff.inHours} hr';
    if (diff.inDays < 7) return '${diff.inDays} d';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({required this.name, required this.photoUrl});

  final String name;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? 'P'
        : name.trim().substring(0, 1).toUpperCase();

    if (photoUrl.isNotEmpty) {
      return CircleAvatar(radius: 28, backgroundImage: NetworkImage(photoUrl));
    }

    return CircleAvatar(
      radius: 28,
      backgroundColor: const Color(0xFFF4EFEA),
      child: Text(
        initials,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
      ),
    );
  }
}

class _MessagesStateMessage extends StatelessWidget {
  const _MessagesStateMessage({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        SocialBottomNav.contentBottomPadding(context),
      ),
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
                  Icons.chat_bubble_outline_rounded,
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
