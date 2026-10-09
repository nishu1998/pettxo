import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../domain/models/chat_image_attachment.dart';

const int maxPrivateChatImageReadBytes = 3 * 1024 * 1024;

class ChatImageUploadProgress {
  const ChatImageUploadProgress({
    required this.bytesTransferred,
    required this.totalBytes,
  });

  final int bytesTransferred;
  final int totalBytes;

  double get fraction => totalBytes <= 0
      ? 0
      : (bytesTransferred / totalBytes).clamp(0, 1).toDouble();
}

class ChatImageUploadOperation {
  ChatImageUploadOperation(UploadTask task)
    : this.testing(
        progress: task.snapshotEvents.map(
          (snapshot) => ChatImageUploadProgress(
            bytesTransferred: snapshot.bytesTransferred,
            totalBytes: snapshot.totalBytes,
          ),
        ),
        completed: task.then<void>((_) {}),
        cancel: task.cancel,
      );

  ChatImageUploadOperation.testing({
    required Stream<ChatImageUploadProgress> progress,
    required Future<void> completed,
    required Future<bool> Function() cancel,
  }) : _progress = progress,
       _completed = completed,
       _cancel = cancel;

  final Stream<ChatImageUploadProgress> _progress;
  final Future<void> _completed;
  final Future<bool> Function() _cancel;

  Stream<ChatImageUploadProgress> get progress => _progress;

  Future<void> get completed => _completed;

  Future<bool> cancel() => _cancel();
}

class ChatMediaRepository {
  ChatMediaRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       _storage = storage ?? FirebaseStorage.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  String newMessageId(String chatId) => _firestore
      .collection('chats')
      .doc(chatId.trim())
      .collection('messages')
      .doc()
      .id;

  String storagePath(String chatId, String messageId) =>
      'chatMedia/${chatId.trim()}/${messageId.trim()}/image.jpg';

  Future<bool> isImageMessagingEnabled(String chatId) async {
    final callable = _functions.httpsCallable(
      'getChatImageMessagingCapability',
    );
    final result = await callable.call<Map<String, dynamic>>({
      'chatId': chatId.trim(),
    });
    return result.data['enabled'] == true;
  }

  ChatImageUploadOperation upload({
    required String chatId,
    required String messageId,
    required ProcessedChatImage image,
  }) {
    final senderId = _auth.currentUser?.uid.trim() ?? '';
    if (senderId.isEmpty) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthenticated',
        message: 'Sign in to send a photo.',
      );
    }
    final path = storagePath(chatId, messageId);
    final task = _storage
        .ref(path)
        .putData(
          image.bytes,
          SettableMetadata(
            contentType: 'image/jpeg',
            customMetadata: {
              'chatId': chatId.trim(),
              'messageId': messageId.trim(),
              'senderId': senderId,
            },
          ),
        );
    return ChatImageUploadOperation(task);
  }

  Future<void> commit({
    required String chatId,
    required String messageId,
    required String storagePath,
  }) async {
    final callable = _functions.httpsCallable('sendChatImageMessage');
    await callable.call<Map<String, dynamic>>({
      'chatId': chatId.trim(),
      'messageId': messageId.trim(),
      'storagePath': storagePath.trim(),
    });
  }

  Future<bool> uploadedObjectExists(String storagePath) async {
    try {
      await _storage.ref(storagePath.trim()).getMetadata();
      return true;
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return false;
      rethrow;
    }
  }

  Future<void> deleteUncommitted(String storagePath) async {
    try {
      await _storage.ref(storagePath.trim()).delete();
    } catch (_) {
      // Best-effort orphan cleanup. Committed media is intentionally denied.
    }
  }
}

class PrivateChatImageCache {
  PrivateChatImageCache._();
  static final PrivateChatImageCache instance = PrivateChatImageCache._();

  final Map<String, Future<Uint8List>> _pending = <String, Future<Uint8List>>{};
  static const int _maxEntries = 24;

  Future<Uint8List> load(String storagePath) {
    final path = storagePath.trim();
    if (path.isEmpty) return Future<Uint8List>.error('Missing image path.');
    final existing = _pending[path];
    if (existing != null) return existing;
    if (_pending.length >= _maxEntries) {
      _pending.remove(_pending.keys.first);
    }
    final future = () async {
      final bytes = await FirebaseStorage.instance
          .ref(path)
          .getData(maxPrivateChatImageReadBytes);
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Image is unavailable.');
      }
      return bytes;
    }();
    _pending[path] = future;
    return future;
  }

  void evict(String storagePath) {
    _pending.remove(storagePath.trim());
  }
}
