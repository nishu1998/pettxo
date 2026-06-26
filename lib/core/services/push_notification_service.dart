import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../features/bookings/domain/models/booking_flow_models.dart';
import '../../features/bookings/presentation/screens/booking_detail_screen.dart';
import '../../features/messages/presentation/screens/chat_detail_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../constants/app_colors.dart';
import 'app_loader.dart';

@pragma('vm:entry-point')
Future<void> pettxoFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp();
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-south1',
  );

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<RemoteMessage>? _messageOpenedAppSubscription;
  String? _currentUid;
  String? _currentToken;
  OverlayEntry? _foregroundBannerEntry;
  Timer? _foregroundBannerTimer;
  final Set<String> _handledMessageKeys = <String>{};

  String _maskToken(String token) {
    if (token.isEmpty) return '';
    if (token.length <= 4) return token;
    return '${'*' * (token.length - 4)}${token.substring(token.length - 4)}';
  }

  Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(
      pettxoFirebaseMessagingBackgroundHandler,
    );

    await _requestPermission();
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _authSubscription ??= _auth.authStateChanges().listen(_syncForUser);
    _tokenRefreshSubscription ??= _messaging.onTokenRefresh.listen((token) {
      final previousToken = _currentToken;
      _currentToken = token;
      final uid = _auth.currentUser?.uid;
      debugPrint(
        'PushNotificationService token refresh debug -> uid=${uid ?? ''}, tokenMasked=${_maskToken(token)}',
      );
      if (uid != null) {
        unawaited(
          _handleTokenRefresh(
            uid: uid,
            previousToken: previousToken,
            newToken: token,
          ),
        );
      }
    });
    _foregroundMessageSubscription ??= FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    _messageOpenedAppSubscription ??= FirebaseMessaging.onMessageOpenedApp
        .listen((message) {
          _handleNotificationTap(message);
        });

    try {
      await _syncForUser(_auth.currentUser);
    } catch (error, stackTrace) {
      debugPrint(
        'PushNotificationService initialize debug -> initial sync failed: $error\n$stackTrace',
      );
    }
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleNotificationTap(initialMessage);
      });
    }
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
  }

  Future<void> _syncForUser(User? user) async {
    final previousUid = _currentUid;
    final previousToken = _currentToken;
    debugPrint(
      'PushNotificationService auth sync debug -> nextUserId=${user?.uid ?? ''}, previousUserId=${previousUid ?? ''}, previousTokenMasked=${previousToken == null ? '' : _maskToken(previousToken)}',
    );

    if (user == null) {
      if (previousUid != null && previousToken != null) {
        await _removeToken(previousUid, previousToken);
      }
      _currentUid = null;
      _currentToken = null;
      return;
    }

    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      debugPrint(
        'PushNotificationService auth sync debug -> no registration token available for uid=${user.uid}',
      );
      return;
    }

    if (previousUid != null && previousToken != null) {
      final shouldRemovePreviousToken =
          previousUid != user.uid || previousToken != token;
      if (shouldRemovePreviousToken) {
        await _removeToken(previousUid, previousToken);
      }
    }

    _currentUid = user.uid;
    _currentToken = token;
    try {
      await _storeToken(user.uid, token);
    } catch (error, stackTrace) {
      debugPrint(
        'PushNotificationService auth sync debug -> token sync failed for uid=${user.uid}: $error\n$stackTrace',
      );
    }
  }

  Future<void> _handleTokenRefresh({
    required String uid,
    required String? previousToken,
    required String newToken,
  }) async {
    try {
      if (previousToken != null &&
          previousToken.isNotEmpty &&
          previousToken != newToken) {
        await _removeToken(uid, previousToken);
      }
      await _storeToken(uid, newToken);
    } catch (error, stackTrace) {
      debugPrint(
        'PushNotificationService token refresh debug -> sync failed for uid=$uid: $error\n$stackTrace',
      );
    }
  }

  Future<void> unregisterCurrentDeviceTokenForLogout() async {
    final uid = (_auth.currentUser?.uid ?? _currentUid ?? '').trim();
    final token = (_currentToken ?? await _messaging.getToken() ?? '').trim();
    debugPrint(
      'PushNotificationService logout token removal debug -> uid=$uid, tokenMasked=${token.isEmpty ? '' : _maskToken(token)}',
    );
    if (uid.isEmpty || token.isEmpty) return;

    await _removeToken(uid, token);
    if (_currentUid == uid) {
      _currentUid = null;
    }
    if (_currentToken == token) {
      _currentToken = null;
    }
  }

  Future<void> _storeToken(String uid, String token) async {
    final callable = _functions.httpsCallable('syncNotificationToken');
    final result = await callable.call<Map<String, dynamic>>({
      'token': token,
      'platform': _platformName,
    });
    final data = Map<String, dynamic>.from(result.data);
    final removedFromUserIds =
        (data['removedFromUserIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString())
            .toList(growable: false);
    final savedToUserId = (data['savedToUserId'] as String? ?? '').trim();
    debugPrint(
      'PushNotificationService token registration debug -> currentUserId=$uid, tokenMasked=${_maskToken(token)}, removedFromUserIds=$removedFromUserIds, savedToUserId=$savedToUserId',
    );
  }

  Future<void> _removeToken(String uid, String token) async {
    debugPrint(
      'PushNotificationService token removal debug -> uid=$uid, tokenMasked=${_maskToken(token)}',
    );
    final callable = _functions.httpsCallable('removeNotificationToken');
    final result = await callable.call<Map<String, dynamic>>({'token': token});
    final data = Map<String, dynamic>.from(result.data);
    final removedFromUserIds =
        (data['removedFromUserIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString())
            .toList(growable: false);
    debugPrint(
      'PushNotificationService token removal debug -> currentUserId=$uid, tokenMasked=${_maskToken(token)}, removedFromUserIds=$removedFromUserIds',
    );
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final currentUserId = _auth.currentUser?.uid.trim() ?? '';
    final senderId = _stringValue(message.data['senderId']);
    final type = _stringValue(message.data['type']);
    final category = _stringValue(message.data['category']);
    if (currentUserId.isNotEmpty &&
        senderId.isNotEmpty &&
        currentUserId == senderId &&
        (type == 'chat' || type == 'chatMessage' || category == 'chat')) {
      debugPrint(
        'PushNotificationService foreground banner skipped -> currentUserId=$currentUserId, senderId=$senderId, type=$type, category=$category',
      );
      return;
    }

    final title = _firstNonEmpty(
      message.notification?.title,
      message.data['title'],
      'Pettxo update',
    );
    final body = _firstNonEmpty(
      message.notification?.body,
      message.data['body'],
      'You have a new notification.',
    );
    debugPrint(
      'PushNotificationService foreground banner debug -> currentUserId=$currentUserId, senderId=$senderId, type=$type, category=$category, chatId=${_stringValue(message.data['chatId'])}',
    );

    final overlayState = AppLoader.navigatorKey.currentState?.overlay;
    if (overlayState == null) return;

    _foregroundBannerTimer?.cancel();
    _foregroundBannerEntry?.remove();

    _foregroundBannerEntry = OverlayEntry(
      builder: (context) {
        return _PushNotificationBanner(
          title: title,
          body: body,
          onTap: () {
            _dismissForegroundBanner();
            _handleNotificationTap(message);
          },
          onDismiss: _dismissForegroundBanner,
        );
      },
    );

    overlayState.insert(_foregroundBannerEntry!);
    _foregroundBannerTimer = Timer(const Duration(seconds: 4), () {
      _dismissForegroundBanner();
    });
  }

  void _dismissForegroundBanner() {
    _foregroundBannerTimer?.cancel();
    _foregroundBannerTimer = null;
    _foregroundBannerEntry?.remove();
    _foregroundBannerEntry = null;
  }

  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final key = _messageKeyFor(message);
    if (!_handledMessageKeys.add(key)) return;

    debugPrint(
      'PushNotificationService notification tap debug -> key=$key, type=${_stringValue(data['type'])}, chatId=${_stringValue(data['chatId'])}, senderId=${_stringValue(data['senderId'])}',
    );
    _dismissForegroundBanner();
    _navigateFromPayload(data);
  }

  String _messageKeyFor(RemoteMessage message) {
    return _firstNonEmpty(
      message.data['notificationId'],
      message.messageId,
      '${message.sentTime?.millisecondsSinceEpoch ?? 0}:${message.data}',
    );
  }

  void _navigateFromPayload(Map<String, dynamic> data) {
    final navigator = AppLoader.navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateFromPayload(data);
      });
      return;
    }

    final type = _stringValue(data['type']);
    final bookingId = _stringValue(data['bookingId']);
    final chatId = _stringValue(data['chatId']);
    final senderId = _stringValue(data['senderId']);
    final recipientId = _stringValue(data['recipientId']);
    final recipientRole = _stringValue(data['recipientRole']);

    debugPrint(
      'PushNotificationService navigate debug -> type=$type, chatId=$chatId, senderId=$senderId, recipientId=$recipientId, recipientRole=$recipientRole',
    );

    if ((type == 'chat' || type == 'chatMessage') && chatId.isNotEmpty) {
      navigator.push(
        MaterialPageRoute(builder: (_) => ChatDetailScreen(chatId: chatId)),
      );
      return;
    }

    if (bookingId.isNotEmpty) {
      navigator.push(
        MaterialPageRoute(
          builder: (_) => BookingDetailScreen(
            bookingId: bookingId,
            contextMode: recipientRole == 'provider'
                ? BookingContextMode.delivering
                : BookingContextMode.receiving,
          ),
        ),
      );
      return;
    }

    if (type == 'socialFollow' && senderId.isNotEmpty) {
      navigator.push(
        MaterialPageRoute(builder: (_) => ProfileScreen(userId: senderId)),
      );
      return;
    }

    if ((type == 'socialLike' || type == 'socialComment') &&
        recipientId.isNotEmpty) {
      navigator.push(
        MaterialPageRoute(builder: (_) => ProfileScreen(userId: recipientId)),
      );
      return;
    }

    navigator.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  String _stringValue(Object? value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  String _firstNonEmpty(String? a, String? b, String fallback) {
    final first = (a ?? '').trim();
    if (first.isNotEmpty) return first;
    final second = (b ?? '').trim();
    if (second.isNotEmpty) return second;
    return fallback;
  }
}

class _PushNotificationBanner extends StatelessWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _PushNotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
              child: Ink(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.98),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.14),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.primary, AppColors.secondary],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.notifications_active_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textDark,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textGrey,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onDismiss,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textGrey,
                        ),
                        tooltip: 'Dismiss',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
