import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/bookings/domain/models/booking_flow_models.dart';
import '../../features/bookings/presentation/screens/booking_detail_screen.dart';
import '../../features/messages/presentation/screens/chat_detail_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../constants/app_colors.dart';
import 'app_loader.dart';
import 'network_status_service.dart';

@pragma('vm:entry-point')
Future<void> pettxoFirebaseMessagingBackgroundHandler(
  RemoteMessage message,
) async {
  await Firebase.initializeApp();
}

@pragma('vm:entry-point')
void pettxoLocalNotificationTapBackground(NotificationResponse response) {}

class _AndroidChannelSpec {
  final String id;
  final String name;
  final String description;
  final Importance importance;
  final Priority priority;

  const _AndroidChannelSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.importance,
    required this.priority,
  });
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();
  static const String _generalChannelId = 'pettxo_general_notifications';
  static const String _chatChannelId = 'pettxo_chat_messages';
  static const String _bookingsChannelId = 'pettxo_bookings_payments';
  static const String _socialChannelId = 'pettxo_social_activity';
  static const String _otherChannelId = 'pettxo_other_updates';

  static const String _chatGroupKey = 'pettxo_group_chat';
  static const String _bookingsGroupKey = 'pettxo_group_bookings_payments';
  static const String _socialGroupKey = 'pettxo_group_social';
  static const String _otherGroupKey = 'pettxo_group_other';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
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
  final Map<String, List<String>> _localGroupInboxLines =
      <String, List<String>>{};
  bool _networkRetryListenerAttached = false;
  bool _localNotificationsInitialized = false;

  String _maskToken(String token) {
    if (token.isEmpty) return '';
    if (token.length <= 4) return token;
    return '${'*' * (token.length - 4)}${token.substring(token.length - 4)}';
  }

  void _debugLog(String message) {
    if (!kDebugMode) return;
    debugPrint(message);
  }

  Future<void> initialize() async {
    await _initializeLocalNotifications();
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
      _debugLog(
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
    if (!_networkRetryListenerAttached) {
      _networkRetryListenerAttached = true;
      NetworkStatusService.instance.isOnlineListenable.addListener(() {
        if (NetworkStatusService.instance.isOffline) return;
        final user = _auth.currentUser;
        if (user == null) return;
        _debugLog(
          'PushNotificationService network debug -> online restored, retrying token sync for uid=${user.uid}',
        );
        unawaited(_syncForUser(user));
      });
    }

    try {
      await forceSyncCurrentUser(reason: 'app-start');
    } catch (error, stackTrace) {
      _debugLog(
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

  Future<void> _initializeLocalNotifications() async {
    if (kIsWeb || _localNotificationsInitialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        _handleLocalNotificationPayload(payload);
      },
      onDidReceiveBackgroundNotificationResponse:
          pettxoLocalNotificationTapBackground,
    );

    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    final payload = launchDetails?.notificationResponse?.payload;
    if (payload != null && payload.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleLocalNotificationPayload(payload);
      });
    }

    _localNotificationsInitialized = true;
  }

  Future<void> _requestPermission() async {
    if (NetworkStatusService.instance.isOffline) {
      _debugLog(
        'PushNotificationService permission debug -> skipped while offline',
      );
      return;
    }
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    _debugLog(
      'PushNotificationService permission debug -> status=${settings.authorizationStatus.name}, '
      'alert=${settings.alert}, badge=${settings.badge}, sound=${settings.sound}',
    );
  }

  Future<void> _syncForUser(User? user) async {
    final previousUid = _currentUid;
    final previousToken = _currentToken;
    _debugLog(
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

    if (NetworkStatusService.instance.isOffline) {
      _debugLog(
        'PushNotificationService auth sync debug -> token update skipped offline for uid=${user.uid}',
      );
      _currentUid = user.uid;
      return;
    }

    final token = await _messaging.getToken();
    if (token == null || token.isEmpty) {
      _debugLog(
        'PushNotificationService auth sync debug -> no registration token available for uid=${user.uid}',
      );
      return;
    }
    _debugLog(
      'PushNotificationService auth sync debug -> fetched token for uid=${user.uid}, tokenMasked=${_maskToken(token)}',
    );

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
      _debugLog(
        'PushNotificationService auth sync debug -> token sync failed for uid=${user.uid}: $error\n$stackTrace',
      );
    }
  }

  Future<void> _handleTokenRefresh({
    required String uid,
    required String? previousToken,
    required String newToken,
  }) async {
    if (NetworkStatusService.instance.isOffline) {
      _debugLog(
        'PushNotificationService token refresh debug -> skipped offline for uid=$uid',
      );
      return;
    }
    try {
      if (previousToken != null &&
          previousToken.isNotEmpty &&
          previousToken != newToken) {
        await _removeToken(uid, previousToken);
      }
      await _storeToken(uid, newToken);
    } catch (error, stackTrace) {
      _debugLog(
        'PushNotificationService token refresh debug -> sync failed for uid=$uid: $error\n$stackTrace',
      );
    }
  }

  Future<void> unregisterCurrentDeviceTokenForLogout() async {
    if (NetworkStatusService.instance.isOffline) {
      _debugLog(
        'PushNotificationService logout token removal debug -> skipped offline',
      );
      _currentUid = null;
      _currentToken = null;
      return;
    }
    final uid = (_auth.currentUser?.uid ?? _currentUid ?? '').trim();
    final token = (_currentToken ?? await _messaging.getToken() ?? '').trim();
    _debugLog(
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

  Future<void> forceSyncCurrentUser({String reason = 'manual'}) async {
    final user = _auth.currentUser;
    _debugLog(
      'PushNotificationService force sync debug -> reason=$reason, currentUserId=${user?.uid ?? ''}',
    );
    await _syncForUser(user);
  }

  Future<void> _storeToken(String uid, String token) async {
    if (NetworkStatusService.instance.isOffline) {
      _debugLog(
        'PushNotificationService token registration debug -> skipped offline for uid=$uid',
      );
      return;
    }
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
    final savedPath = (data['savedPath'] as String? ?? '').trim();
    _debugLog(
      'PushNotificationService token registration debug -> currentUserId=$uid, tokenMasked=${_maskToken(token)}, removedFromUserIds=$removedFromUserIds, savedToUserId=$savedToUserId, savedPath=$savedPath',
    );
  }

  Future<void> _removeToken(String uid, String token) async {
    if (NetworkStatusService.instance.isOffline) {
      _debugLog(
        'PushNotificationService token removal debug -> skipped offline for uid=$uid',
      );
      return;
    }
    _debugLog(
      'PushNotificationService token removal debug -> uid=$uid, tokenMasked=${_maskToken(token)}',
    );
    final callable = _functions.httpsCallable('removeNotificationToken');
    final result = await callable.call<Map<String, dynamic>>({'token': token});
    final data = Map<String, dynamic>.from(result.data);
    final removedFromUserIds =
        (data['removedFromUserIds'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString())
            .toList(growable: false);
    final removedPaths =
        (data['removedPaths'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString())
            .toList(growable: false);
    _debugLog(
      'PushNotificationService token removal debug -> currentUserId=$uid, tokenMasked=${_maskToken(token)}, removedFromUserIds=$removedFromUserIds, removedPaths=$removedPaths',
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

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final currentUserId = _auth.currentUser?.uid.trim() ?? '';
    final senderId = _stringValue(message.data['senderId']);
    final type = _stringValue(message.data['type']);
    final category = _stringValue(message.data['category']);
    if (currentUserId.isNotEmpty &&
        senderId.isNotEmpty &&
        currentUserId == senderId &&
        (type == 'chat' || type == 'chatMessage' || category == 'chat')) {
      _debugLog(
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

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _showAndroidGroupedNotification(
        message: message,
        title: title,
        body: body,
      );
      return;
    }

    _debugLog(
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

    _debugLog(
      'PushNotificationService notification tap debug -> key=$key, type=${_stringValue(data['type'])}, chatId=${_stringValue(data['chatId'])}, senderId=${_stringValue(data['senderId'])}',
    );
    _dismissForegroundBanner();
    _navigateFromPayload(data);
  }

  void _handleLocalNotificationPayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) return;
      _dismissForegroundBanner();
      _navigateFromPayload(decoded);
    } catch (error) {
      _debugLog(
        'PushNotificationService local notification payload debug -> parse failed: $error',
      );
    }
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

    _debugLog(
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

  Future<void> _showAndroidGroupedNotification({
    required RemoteMessage message,
    required String title,
    required String body,
  }) async {
    await _initializeLocalNotifications();

    final normalizedType = _normalizedNotificationType(
      _stringValue(message.data['type']),
      _stringValue(message.data['category']),
    );
    final channel = _channelSpecForType(normalizedType);
    final groupKey = _groupKeyForType(normalizedType);
    final payload = jsonEncode(message.data);
    final notificationId = _stableNotificationId(_messageKeyFor(message));

    final lines = _localGroupInboxLines.putIfAbsent(groupKey, () => <String>[]);
    final previewLine = body.isEmpty ? title : '$title - $body';
    lines.add(previewLine);
    if (lines.length > 5) {
      lines.removeRange(0, lines.length - 5);
    }

    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.priority,
      groupKey: groupKey,
      styleInformation: const DefaultStyleInformation(true, true),
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      channelShowBadge: true,
    );

    await _localNotifications.show(
      notificationId,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: payload,
    );

    if (lines.length < 2) return;

    final summaryDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.priority,
      groupKey: groupKey,
      setAsGroupSummary: true,
      styleInformation: InboxStyleInformation(
        lines.reversed.take(5).toList(growable: false),
        contentTitle: _summaryTitleForGroup(groupKey, lines.length),
        summaryText: '${lines.length} notifications',
      ),
      playSound: false,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      channelShowBadge: true,
    );

    await _localNotifications.show(
      _stableNotificationId('summary_$groupKey'),
      _summaryTitleForGroup(groupKey, lines.length),
      '${lines.length} new notifications',
      NotificationDetails(android: summaryDetails),
      payload: payload,
    );
  }

  String _normalizedNotificationType(String type, String category) {
    final trimmedType = type.trim();
    final trimmedCategory = category.trim();
    if (trimmedCategory == 'chat' || trimmedType == 'chatMessage') {
      return 'chat';
    }
    return trimmedType;
  }

  _AndroidChannelSpec _channelSpecForType(String notificationType) {
    switch (notificationType) {
      case 'chat':
      case 'message':
      case 'providerChat':
        return const _AndroidChannelSpec(
          id: _chatChannelId,
          name: '💬 Chat Messages',
          description: 'Direct chat and provider/customer messages.',
          importance: Importance.high,
          priority: Priority.high,
        );
      case 'bookingRequest':
      case 'bookingAccepted':
      case 'bookingRejected':
      case 'bookingCancelled':
      case 'bookingReminder':
      case 'paymentSuccess':
      case 'paymentFailed':
      case 'refund':
      case 'payout':
        return const _AndroidChannelSpec(
          id: _bookingsChannelId,
          name: '📅 Bookings & Payments',
          description: 'Booking requests, updates, and payment alerts.',
          importance: Importance.high,
          priority: Priority.high,
        );
      case 'socialLike':
      case 'socialComment':
      case 'socialFollow':
      case 'like':
      case 'comment':
      case 'follow':
        return const _AndroidChannelSpec(
          id: _socialChannelId,
          name: '❤️ Social Activity',
          description: 'Likes, comments, follows, and social activity.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        );
      case 'general':
      case 'promotion':
      case 'announcement':
        return const _AndroidChannelSpec(
          id: _otherChannelId,
          name: '📢 Other Updates',
          description: 'Announcements, promotions, and Pettxo updates.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        );
      default:
        return const _AndroidChannelSpec(
          id: _generalChannelId,
          name: 'Pettxo Alerts',
          description: 'General Pettxo notifications.',
          importance: Importance.high,
          priority: Priority.high,
        );
    }
  }

  String _groupKeyForType(String notificationType) {
    switch (notificationType) {
      case 'chat':
      case 'message':
      case 'providerChat':
        return _chatGroupKey;
      case 'bookingRequest':
      case 'bookingAccepted':
      case 'bookingRejected':
      case 'bookingCancelled':
      case 'bookingReminder':
      case 'paymentSuccess':
      case 'paymentFailed':
      case 'refund':
      case 'payout':
        return _bookingsGroupKey;
      case 'socialLike':
      case 'socialComment':
      case 'socialFollow':
      case 'like':
      case 'comment':
      case 'follow':
        return _socialGroupKey;
      case 'general':
      case 'promotion':
      case 'announcement':
        return _otherGroupKey;
      default:
        return _otherGroupKey;
    }
  }

  String _summaryTitleForGroup(String groupKey, int count) {
    switch (groupKey) {
      case _chatGroupKey:
        return '$count chat messages';
      case _bookingsGroupKey:
        return '$count booking updates';
      case _socialGroupKey:
        return '$count social updates';
      case _otherGroupKey:
        return '$count Pettxo updates';
      default:
        return '$count notifications';
    }
  }

  int _stableNotificationId(String source) {
    return source.hashCode & 0x7fffffff;
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
