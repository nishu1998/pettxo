import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/chat_model.dart';
import '../../domain/models/message_model.dart';

class ChatMessagePage {
  final List<MessageModel> messages;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  const ChatMessagePage({
    required this.messages,
    required this.cursor,
    required this.hasMore,
  });
}

class ChatRepository {
  ChatRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  Stream<List<ChatModel>> watchChatsFor(String currentUid, {int limit = 40}) {
    final uid = currentUid.trim();
    if (uid.isEmpty) return Stream.value(const []);

    debugPrint(
      'ChatRepository watchChatsFor debug -> currentUserId=$uid, path=chats, arrayContains=participantIds, orderBy=lastMessageAt desc, limit=$limit',
    );

    return _firestore
        .collection('chats')
        .where('participantIds', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final chats = snapshot.docs
              .map(ChatModel.fromDocument)
              .toList(growable: false);
          final dedupedByPair = <String, ChatModel>{};

          for (final chat in chats) {
            final pairKey = [...chat.participantIds]..sort();
            final dedupeKey = pairKey.join('_');
            final existing = dedupedByPair[dedupeKey];
            if (existing == null) {
              dedupedByPair[dedupeKey] = chat;
              continue;
            }

            final preferCurrent =
                chat.id.startsWith('chat_') && !existing.id.startsWith('chat_');
            final currentTime =
                chat.lastMessageAt ?? chat.updatedAt ?? chat.createdAt;
            final existingTime =
                existing.lastMessageAt ??
                existing.updatedAt ??
                existing.createdAt;
            final isNewer =
                (currentTime?.millisecondsSinceEpoch ?? 0) >
                (existingTime?.millisecondsSinceEpoch ?? 0);

            if (preferCurrent ||
                (!existing.id.startsWith('chat_') && isNewer)) {
              dedupedByPair[dedupeKey] = chat;
            }
          }

          final result = dedupedByPair.values.toList(growable: false);
          result.sort((a, b) {
            final aTime = a.lastMessageAt ?? a.updatedAt ?? a.createdAt;
            final bTime = b.lastMessageAt ?? b.updatedAt ?? b.createdAt;
            return (bTime?.millisecondsSinceEpoch ?? 0).compareTo(
              aTime?.millisecondsSinceEpoch ?? 0,
            );
          });
          return result;
        });
  }

  Stream<ChatModel?> watchChat(String chatId) {
    final id = chatId.trim();
    if (id.isEmpty) return Stream.value(null);

    return _firestore.collection('chats').doc(id).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return ChatModel.fromDocument(snapshot);
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRecentMessageSnapshots(
    String chatId, {
    int limit = 30,
  }) {
    final id = chatId.trim();
    if (id.isEmpty) {
      return const Stream.empty();
    }

    return _firestore
        .collection('chats')
        .doc(id)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<ChatMessagePage> fetchOlderMessages(
    String chatId, {
    required DocumentSnapshot<Map<String, dynamic>> startAfter,
    int limit = 30,
  }) async {
    final id = chatId.trim();
    if (id.isEmpty) {
      return const ChatMessagePage(messages: [], cursor: null, hasMore: false);
    }

    final snapshot = await _firestore
        .collection('chats')
        .doc(id)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .startAfterDocument(startAfter)
        .limit(limit)
        .get();

    return ChatMessagePage(
      messages: snapshot.docs
          .map(MessageModel.fromDocument)
          .toList(growable: false),
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length >= limit,
    );
  }

  Future<String> startProviderChat({required String serviceId}) async {
    final currentUserId = _auth.currentUser?.uid.trim() ?? '';
    final trimmedServiceId = serviceId.trim();
    if (currentUserId.isEmpty) {
      throw Exception('Please sign in again and try once more.');
    }
    if (trimmedServiceId.isEmpty) {
      throw Exception('Service not found.');
    }

    debugPrint(
      'ChatRepository startProviderChat debug -> serviceId=$trimmedServiceId, currentUserId=$currentUserId',
    );

    final serviceSnapshot = await _firestore
        .collection('services')
        .doc(trimmedServiceId)
        .get();
    final service = serviceSnapshot.data() ?? const <String, dynamic>{};
    debugPrint(
      'ChatRepository startProviderChat debug -> providerId=${(service['ownerUserId'] as String? ?? '').trim()}, '
      'status=${(service['status'] as String? ?? '').trim()}, '
      'isActive=${service['isActive']}, '
      'isVisibleToMarketplace=${service['isVisibleToMarketplace']}, '
      'isDeleted=${service['isDeleted']}, '
      'isPaused=${service['isPaused']}, '
      'isPausedByVerification=${service['isPausedByVerification']}',
    );

    final callable = _functions.httpsCallable('startProviderChat');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'serviceId': trimmedServiceId,
      });
      final chatId = (result.data['chatId'] as String? ?? '').trim();
      debugPrint(
        'ChatRepository startProviderChat debug -> callable chatId=$chatId',
      );
      return chatId;
    } catch (error, stackTrace) {
      debugPrint(
        'ChatRepository startProviderChat debug -> callable exception=$error\n$stackTrace',
      );
      rethrow;
    }
  }

  Future<String> startDirectUserChat({required String otherUserId}) async {
    final currentUserId = _auth.currentUser?.uid.trim() ?? '';
    final trimmedOtherUserId = otherUserId.trim();
    if (currentUserId.isEmpty) {
      throw Exception('Please sign in again and try once more.');
    }
    if (trimmedOtherUserId.isEmpty) {
      throw Exception('User profile not found.');
    }
    if (currentUserId == trimmedOtherUserId) {
      throw Exception('You cannot message yourself.');
    }

    final orderedParticipantIds = [currentUserId, trimmedOtherUserId]..sort();
    final chatId = 'chat_${orderedParticipantIds.join('_')}';
    debugPrint(
      'ChatRepository startDirectUserChat debug -> currentUserId=$currentUserId, profileUserId=$trimmedOtherUserId, deterministicChatId=$chatId',
    );

    final callable = _functions.httpsCallable('startDirectUserChat');
    try {
      final result = await callable.call<Map<String, dynamic>>({
        'otherUserId': trimmedOtherUserId,
      });
      final resolvedChatId = (result.data['chatId'] as String? ?? '').trim();
      debugPrint(
        'ChatRepository startDirectUserChat debug -> callable chatId=$resolvedChatId',
      );
      return resolvedChatId;
    } catch (error, stackTrace) {
      debugPrint(
        'ChatRepository startDirectUserChat debug -> callable exception=$error\n$stackTrace',
      );
      rethrow;
    }
  }

  Future<void> sendChatMessage({
    required String chatId,
    required String text,
    String? sourceServiceId,
  }) async {
    final callable = _functions.httpsCallable('sendChatMessage');
    await callable.call<Map<String, dynamic>>({
      'chatId': chatId.trim(),
      'text': text.trim(),
      if (sourceServiceId != null && sourceServiceId.trim().isNotEmpty)
        'sourceServiceId': sourceServiceId.trim(),
    });
  }

  Future<void> markChatDelivered({required String chatId}) async {
    final callable = _functions.httpsCallable('markChatDelivered');
    await callable.call<Map<String, dynamic>>({'chatId': chatId.trim()});
  }

  Future<void> markChatRead({required String chatId}) async {
    final callable = _functions.httpsCallable('markChatRead');
    await callable.call<Map<String, dynamic>>({'chatId': chatId.trim()});
  }
}
