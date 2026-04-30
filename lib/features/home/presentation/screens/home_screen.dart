import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/navigation/social_app_tab.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../../../core/widgets/social_bottom_nav.dart';
import '../../../feed/data/repositories/feed_mock_repository.dart';
import '../../../offers/data/services/offer_service.dart';
import '../../../offers/presentation/screens/offer_wall_screen.dart';
import '../../../offers/presentation/widgets/offer_popup_dialog.dart';
import '../../../feed/presentation/widgets/feed_post_card.dart';
import '../../../restrictions/data/services/user_restriction_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final OfferService _offerService = OfferService();
  bool _checkedOffers = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showEligibleOffers();
    });
  }

  Future<void> _showEligibleOffers() async {
    if (_checkedOffers || !mounted) return;
    _checkedOffers = true;

    try {
      final result = await _offerService.getEligibleOffers(screen: 'home');
      if (!mounted) return;

      final offerWall = result.offerWall;
      if (offerWall != null &&
          await _offerService.shouldShowOffer(offerWall.id)) {
        await _offerService.markOfferShown(offerWall.id);
        if (!mounted) return;
        final claimed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => OfferWallScreen(offer: offerWall)),
        );
        if (!mounted) return;
        if (claimed == true) {
          AppFeedback.show(
            context,
            message: 'Offer claimed successfully.',
            tone: AppFeedbackTone.success,
          );
        } else {
          await _offerService.recordOfferDismissed(offerWall.id);
        }
        return;
      }

      final popup = result.popup;
      if (popup != null && await _offerService.shouldShowOffer(popup.id)) {
        await _offerService.markOfferShown(popup.id);
        if (!mounted) return;
        final claimed = await OfferPopupDialog.show(context, offer: popup);
        if (!mounted) return;
        if (claimed == true) {
          AppFeedback.show(
            context,
            message: 'Offer claimed successfully.',
            tone: AppFeedbackTone.success,
          );
        } else {
          await _offerService.recordOfferDismissed(popup.id);
        }
      }
    } catch (_) {
      // Offer fetch failures should not interrupt the home experience.
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = const FeedMockRepository().getPosts();
    final topInset = MediaQuery.paddingOf(context).top;
    const topBarHeight = 76.0;
    final topContentPadding = topInset + topBarHeight + 24;
    final bottomContentPadding = SocialBottomNav.contentBottomPadding(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody: true,
      body: Stack(
        children: [
          // The feed is painted edge-to-edge first so it can scroll behind the
          // floating header and bottom nav overlays.
          ListView.separated(
            padding: EdgeInsets.fromLTRB(
              16,
              topContentPadding,
              16,
              bottomContentPadding,
            ),
            itemCount: posts.length,
            separatorBuilder: (context, index) => const SizedBox(height: 18),
            itemBuilder: (context, index) {
              return FeedPostCard(post: posts[index]);
            },
          ),
          // Safe-area spacing is applied to the overlay itself instead of the
          // whole body, which keeps the status bar clear while still letting
          // content pass underneath the bar as the user scrolls.
          Positioned(
            left: 16,
            right: 16,
            top: topInset + 10,
            child: GlassSurface(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              borderRadius: BorderRadius.circular(24),
              backgroundColor: Colors.white.withValues(alpha: 0.72),
              blurSigma: 20,
              border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFE9DD), Color(0xFFFFF3EC)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: IconButton(
                      onPressed: () {
                        if (!UserRestrictionService.instance
                            .ensureCanUseSocialFeatures(context)) {
                          return;
                        }
                        Navigator.pushNamed(context, "/create");
                      },
                      icon: const Icon(
                        Icons.add_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: SvgPicture.asset(
                          'assets/brand/pettxo_logo.svg',
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Pettxo",
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.56),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const _NotificationsBellButton(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const SocialBottomNav(activeTab: SocialAppTab.home),
    );
  }
}

class _NotificationsBellButton extends StatefulWidget {
  const _NotificationsBellButton();

  @override
  State<_NotificationsBellButton> createState() =>
      _NotificationsBellButtonState();
}

class _NotificationsBellButtonState extends State<_NotificationsBellButton>
    with SingleTickerProviderStateMixin {
  static const Duration _ringDuration = Duration(milliseconds: 720);
  static const Duration _ringInterval = Duration(seconds: 8);

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _ringDuration,
  );
  late final Animation<double> _rotation = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0,
        end: -0.12,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: -0.12,
        end: 0.1,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.1,
        end: -0.07,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: -0.07,
        end: 0.05,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 0.05,
        end: 0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
  ]).animate(_controller);

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _notificationSubscription;
  Timer? _ringTimer;
  bool _hasUnreadNotifications = false;

  @override
  void initState() {
    super.initState();
    _bindNotificationStream(_auth.currentUser);
    _authSubscription = _auth.authStateChanges().listen(
      _bindNotificationStream,
    );
  }

  @override
  void dispose() {
    _ringTimer?.cancel();
    _notificationSubscription?.cancel();
    _authSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _bindNotificationStream(User? user) {
    _notificationSubscription?.cancel();
    _updateUnreadState(false);

    if (user == null) return;

    _notificationSubscription = _firestore
        .collection('notifications')
        .where('userId', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen((snapshot) {
          final hasUnread = snapshot.docs.any((doc) {
            final data = doc.data();
            return data['read'] != true && data['isRead'] != true;
          });
          _updateUnreadState(hasUnread);
        });
  }

  void _updateUnreadState(bool hasUnread) {
    if (_hasUnreadNotifications == hasUnread) return;
    _hasUnreadNotifications = hasUnread;

    if (hasUnread) {
      _startRingLoop();
    } else {
      _stopRingLoop();
    }
  }

  void _startRingLoop() {
    _ringTimer?.cancel();
    _controller.forward(from: 0);
    _ringTimer = Timer.periodic(_ringInterval, (_) {
      if (!_hasUnreadNotifications || _controller.isAnimating) return;
      _controller.forward(from: 0);
    });
  }

  void _stopRingLoop() {
    _ringTimer?.cancel();
    _ringTimer = null;
    if (_controller.isAnimating || _controller.value != 0) {
      _controller.animateTo(0, duration: const Duration(milliseconds: 160));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () {
        Navigator.pushNamed(context, "/alerts");
      },
      icon: AnimatedBuilder(
        animation: _rotation,
        builder: (context, child) {
          return Transform.rotate(
            angle: _rotation.value,
            alignment: const Alignment(0, -0.65),
            child: Icon(
              Icons.notifications_none_rounded,
              color: _hasUnreadNotifications
                  ? AppColors.primary
                  : AppColors.textDark,
            ),
          );
        },
      ),
    );
  }
}
