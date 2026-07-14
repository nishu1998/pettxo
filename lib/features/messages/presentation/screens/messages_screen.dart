import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_user_avatar.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../data/repositories/chat_repository.dart';
import '../../domain/models/chat_model.dart';
import 'chat_detail_screen.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final ChatRepository _repository = ChatRepository();
  final ProfileRepository _profileRepository = ProfileRepository();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<String, UserProfile> _profilesByUid = <String, UserProfile>{};
  final Map<String, StreamSubscription<UserProfile>>
  _profileSubscriptionsByUid = <String, StreamSubscription<UserProfile>>{};

  bool _isHeaderVisible = true;
  String _searchQuery = '';
  double _lastScrollOffset = 0;
  double _scrollDeltaAccumulator = 0;

  static const double _topBarTopResetOffset = 12;
  static const double _topBarHideThreshold = 32;
  static const double _topBarShowThreshold = 14;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    for (final subscription in _profileSubscriptionsByUid.values) {
      subscription.cancel();
    }
    super.dispose();
  }

  Future<void> _refreshMessages() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;
    await _repository.refreshChatsFor(currentUid);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final direction = position.userScrollDirection;
    final pixels = position.pixels;
    final delta = pixels - _lastScrollOffset;
    _lastScrollOffset = pixels;

    if (pixels <= _topBarTopResetOffset) {
      _scrollDeltaAccumulator = 0;
      if (!_isHeaderVisible && mounted) {
        setState(() => _isHeaderVisible = true);
      }
    } else if (direction == ScrollDirection.reverse && delta > 0) {
      _scrollDeltaAccumulator = (_scrollDeltaAccumulator + delta).clamp(
        0.0,
        _topBarHideThreshold,
      );
      if (_isHeaderVisible &&
          _scrollDeltaAccumulator >= _topBarHideThreshold &&
          mounted) {
        _scrollDeltaAccumulator = 0;
        setState(() => _isHeaderVisible = false);
      }
    } else if (direction == ScrollDirection.forward && delta < 0) {
      _scrollDeltaAccumulator = (_scrollDeltaAccumulator + delta).clamp(
        -_topBarShowThreshold,
        0.0,
      );
      if (!_isHeaderVisible &&
          _scrollDeltaAccumulator <= -_topBarShowThreshold &&
          mounted) {
        _scrollDeltaAccumulator = 0;
        setState(() => _isHeaderVisible = true);
      }
    } else if (direction == ScrollDirection.idle) {
      _scrollDeltaAccumulator = 0;
    }
  }

  void _handleSearchChanged() {
    final nextQuery = _searchController.text.trim();
    if (nextQuery == _searchQuery) return;
    setState(() => _searchQuery = nextQuery);
  }

  List<ChatModel> _filterChats(List<ChatModel> chats, String currentUid) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return chats;
    return chats
        .where((chat) {
          final otherUserId = chat.otherParticipantIdFor(currentUid);
          return _displayNameFor(
            chat,
            currentUid,
            otherUserId,
          ).trim().toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  void _syncProfileSubscriptions(List<ChatModel> chats, String currentUid) {
    final requiredUids = chats
        .map((chat) => chat.otherParticipantIdFor(currentUid).trim())
        .where((uid) => uid.isNotEmpty)
        .toSet();

    final staleUids = _profileSubscriptionsByUid.keys
        .where((uid) => !requiredUids.contains(uid))
        .toList(growable: false);
    for (final uid in staleUids) {
      _profileSubscriptionsByUid.remove(uid)?.cancel();
    }

    for (final uid in requiredUids) {
      if (_profileSubscriptionsByUid.containsKey(uid)) continue;
      _profileSubscriptionsByUid[uid] = _profileRepository
          .watchUserProfile(uid)
          .listen(
            (profile) {
              if (!mounted) return;
              setState(() {
                _profilesByUid[uid] = profile;
              });
            },
            onError: (_) {
              // Keep denormalized chat identity as the safe fallback.
            },
          );
    }
  }

  String _displayNameFor(
    ChatModel chat,
    String currentUid,
    String otherUserId,
  ) {
    final profileName = _profilesByUid[otherUserId]?.name.trim() ?? '';
    if (profileName.isNotEmpty) return profileName;

    final fallbackName = _fallbackNameFor(chat, currentUid, otherUserId).trim();
    return fallbackName.isNotEmpty ? fallbackName : 'Pettxo user';
  }

  String _photoUrlFor(ChatModel chat, String currentUid, String otherUserId) {
    final profilePhoto =
        _profilesByUid[otherUserId]?.profileImageUrl.trim() ?? '';
    if (profilePhoto.isNotEmpty) return profilePhoto;
    return _fallbackPhotoUrlFor(chat, currentUid, otherUserId);
  }

  String _fallbackNameFor(
    ChatModel chat,
    String currentUid,
    String otherUserId,
  ) {
    if (otherUserId == chat.customerId) return chat.customerDisplayName;
    if (otherUserId == chat.providerId) return chat.providerDisplayName;
    return chat.otherParticipantNameFor(currentUid);
  }

  String _fallbackPhotoUrlFor(
    ChatModel chat,
    String currentUid,
    String otherUserId,
  ) {
    if (otherUserId == chat.customerId) return chat.customerPhotoUrl;
    if (otherUserId == chat.providerId) return chat.providerPhotoUrl;
    return chat.otherParticipantPhotoUrlFor(currentUid);
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return SocialTabBackScope(
      activeTab: SocialAppTab.messages,
      child: Scaffold(
        backgroundColor: AppColors.background,
        extendBody: true,
        body: SafeArea(
          child: Column(
            children: [
              ClipRect(
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  alignment: Alignment.topCenter,
                  heightFactor: _isHeaderVisible ? 1 : 0,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOutCubic,
                    offset: _isHeaderVisible
                        ? Offset.zero
                        : const Offset(0, -0.22),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeInOutCubic,
                      opacity: _isHeaderVisible ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !_isHeaderVisible,
                        child: _MessagesHeader(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshMessages,
                  child: currentUid.isEmpty
                      ? _MessagesStateMessage(
                          controller: _scrollController,
                          title: 'Sign in to view messages',
                          message:
                              'Your conversations will appear here once you are signed in.',
                        )
                      : StreamBuilder<List<ChatModel>>(
                          stream: _repository.watchChatsFor(currentUid),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return _MessagesStateMessage(
                                controller: _scrollController,
                                title: 'Unable to load messages',
                                message: 'Please try again in a moment.',
                              );
                            }
                            if (!snapshot.hasData) {
                              return ListView(
                                controller: _scrollController,
                                physics: const BouncingScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                ),
                                padding: EdgeInsets.fromLTRB(
                                  20,
                                  10,
                                  20,
                                  SocialBottomNav.contentBottomPadding(context),
                                ),
                                children: const [
                                  SizedBox(height: 160),
                                  Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              );
                            }

                            final chats = snapshot.data!;
                            _syncProfileSubscriptions(chats, currentUid);
                            if (chats.isEmpty) {
                              return _MessagesStateMessage(
                                controller: _scrollController,
                                title: 'No conversations yet',
                                message:
                                    'Tap "Message Provider" on a service to start chatting.',
                              );
                            }

                            final visibleChats = _filterChats(
                              chats,
                              currentUid,
                            );
                            if (visibleChats.isEmpty) {
                              return _MessagesStateMessage(
                                controller: _scrollController,
                                title: 'No matching conversations',
                                message:
                                    'Try another name or clear search to see all messages.',
                              );
                            }

                            return ListView.separated(
                              controller: _scrollController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: EdgeInsets.fromLTRB(
                                20,
                                10,
                                20,
                                SocialBottomNav.contentBottomPadding(context),
                              ),
                              itemCount: visibleChats.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final chat = visibleChats[index];
                                final otherUserId = chat.otherParticipantIdFor(
                                  currentUid,
                                );
                                final unreadCount = chat.unreadCountFor(
                                  currentUid,
                                );
                                final displayName = _displayNameFor(
                                  chat,
                                  currentUid,
                                  otherUserId,
                                );
                                final photoUrl = _photoUrlFor(
                                  chat,
                                  currentUid,
                                  otherUserId,
                                );

                                return KeyedSubtree(
                                  key: ValueKey<String>(
                                    '${chat.id}_$otherUserId',
                                  ),
                                  child: InkWell(
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
                                        color: Colors.white.withValues(
                                          alpha: 0.94,
                                        ),
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
                                            key: ValueKey<String>(
                                              'avatar_${otherUserId}_$photoUrl',
                                            ),
                                            name: displayName,
                                            photoUrl: photoUrl,
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
                                                        displayName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: AppColors
                                                              .textDark,
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
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            AppColors.textGrey,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  chat.lastMessage.isEmpty
                                                      ? 'Start the conversation'
                                                      : chat.lastMessage,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
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
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: const SocialBottomNav(
          activeTab: SocialAppTab.messages,
        ),
      ),
    );
  }
}

String _relativeTime(DateTime? date) {
  if (date == null) return 'Now';
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'Now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min';
  if (diff.inHours < 24) return '${diff.inHours} hr';
  if (diff.inDays < 7) return '${diff.inDays} d';
  return '${date.day}/${date.month}/${date.year}';
}

class _MessagesHeader extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _MessagesHeader({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      borderRadius: BorderRadius.zero,
      backgroundColor: AppColors.background.withValues(alpha: 0.72),
      blurSigma: 22,
      border: Border(
        bottom: BorderSide(color: Colors.white.withValues(alpha: 0.42)),
      ),
      boxShadow: const [],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Messages',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 12),
          _MessagesSearchBar(controller: controller, focusNode: focusNode),
        ],
      ),
    );
  }
}

class _MessagesSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  const _MessagesSearchBar({required this.controller, required this.focusNode});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      textField: true,
      label: 'Search messages',
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, color: AppColors.textGrey),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search messages',
                  border: InputBorder.none,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.trim().isEmpty) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  tooltip: 'Clear search',
                  onPressed: controller.clear,
                  icon: const Icon(Icons.close_rounded),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({super.key, required this.name, required this.photoUrl});

  final String name;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? 'P'
        : name.trim().substring(0, 1).toUpperCase();

    return AppUserAvatar(
      size: 56,
      imageUrl: photoUrl,
      useCachedImage: false,
      fallback: AppUserAvatarFallback(
        initials: initials,
        backgroundColor: const Color(0xFFF4EFEA),
        textStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textDark,
        ),
      ),
    );
  }
}

class _MessagesStateMessage extends StatelessWidget {
  const _MessagesStateMessage({
    required this.controller,
    required this.title,
    required this.message,
  });

  final ScrollController controller;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: controller,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
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
