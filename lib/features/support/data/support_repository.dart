import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../domain/models/support_models.dart';

class SupportMessagePage {
  const SupportMessagePage({
    required this.messages,
    required this.cursor,
    required this.hasMore,
  });

  final List<SupportTicketMessage> messages;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

class SupportTicketDraftAttachment {
  const SupportTicketDraftAttachment({
    required this.bytes,
    required this.fileName,
    required this.contentType,
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;

  int get fileSize => bytes.length;
}

class SupportUploadedTicketAttachment {
  const SupportUploadedTicketAttachment({
    required this.attachmentId,
    required this.storagePath,
    required this.fileName,
    required this.contentType,
  });

  final String attachmentId;
  final String storagePath;
  final String fileName;
  final String contentType;

  Map<String, String> toCallableMap() {
    return {
      'attachmentId': attachmentId,
      'storagePath': storagePath,
      'fileName': fileName,
      'contentType': contentType,
    };
  }
}

class SupportRepository {
  SupportRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1'),
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  String get currentUid => _auth.currentUser?.uid.trim() ?? '';

  CollectionReference<Map<String, dynamic>> get _tickets =>
      _firestore.collection('supportTickets');

  Stream<List<SupportTicket>> watchMyTickets({int limit = 50}) {
    final uid = currentUid;
    if (uid.isEmpty) return Stream.value(const <SupportTicket>[]);

    return _tickets
        .where('userId', isEqualTo: uid)
        .orderBy('lastMessageAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(SupportTicket.fromDocument)
              .toList(growable: false),
        );
  }

  Future<void> refreshMyTickets({int limit = 50}) async {
    final uid = currentUid;
    if (uid.isEmpty) return;

    await _tickets
        .where('userId', isEqualTo: uid)
        .orderBy('lastMessageAt', descending: true)
        .limit(limit)
        .get(const GetOptions(source: Source.server));
  }

  Stream<SupportTicket?> watchTicket(String ticketId) {
    final id = ticketId.trim();
    if (id.isEmpty) return Stream.value(null);
    return _tickets.doc(id).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return SupportTicket.fromDocument(snapshot);
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchRecentMessageSnapshots(
    String ticketId, {
    int limit = 40,
  }) {
    final id = ticketId.trim();
    if (id.isEmpty) return const Stream.empty();

    return _tickets
        .doc(id)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<SupportMessagePage> fetchOlderMessages(
    String ticketId, {
    required DocumentSnapshot<Map<String, dynamic>> startAfter,
    int limit = 40,
  }) async {
    final id = ticketId.trim();
    if (id.isEmpty) {
      return const SupportMessagePage(
        messages: <SupportTicketMessage>[],
        cursor: null,
        hasMore: false,
      );
    }

    final snapshot = await _tickets
        .doc(id)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .startAfterDocument(startAfter)
        .limit(limit)
        .get();

    return SupportMessagePage(
      messages: snapshot.docs
          .map(SupportTicketMessage.fromDocument)
          .toList(growable: false),
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length >= limit,
    );
  }

  Future<String> createSupportTicket({
    required SupportTicketCategory category,
    required String subject,
    required String description,
    required String contactNumber,
  }) async {
    final callable = _functions.httpsCallable('createSupportTicket');
    final result = await callable.call<Map<String, dynamic>>({
      'category': category.value,
      'subject': subject.trim(),
      'message': description.trim(),
      'contactNumber': contactNumber.trim(),
    });
    return '${result.data['ticketId'] ?? ''}'.trim();
  }

  Future<void> finalizeSupportTicketAttachments({
    required String ticketId,
    required List<SupportUploadedTicketAttachment> attachments,
  }) async {
    if (attachments.isEmpty) return;
    final callable = _functions.httpsCallable(
      'finalizeSupportTicketAttachments',
    );
    await callable.call<Map<String, dynamic>>({
      'ticketId': ticketId.trim(),
      'attachments': attachments.map((item) => item.toCallableMap()).toList(),
    });
  }

  Future<List<SupportUploadedTicketAttachment>> uploadDraftAttachments({
    required String ticketId,
    required List<SupportTicketDraftAttachment> attachments,
  }) async {
    final uid = currentUid;
    if (uid.isEmpty) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthenticated',
        message: 'User not authenticated.',
      );
    }
    if (attachments.isEmpty) return const <SupportUploadedTicketAttachment>[];

    final uploaded = <SupportUploadedTicketAttachment>[];
    for (var index = 0; index < attachments.length; index++) {
      final attachment = attachments[index];
      if (attachment.fileSize == 0) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'missing-file',
          message: 'The selected attachment is empty.',
        );
      }
      if (attachment.fileSize > 5 * 1024 * 1024) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'file-too-large',
          message: 'Each attachment must be 5 MB or smaller.',
        );
      }

      final compressedBytes = await FlutterImageCompress.compressWithList(
        attachment.bytes,
        quality: 84,
        minWidth: 1600,
        minHeight: 1600,
        format: CompressFormat.jpeg,
      );
      if (compressedBytes.isEmpty) {
        throw FirebaseException(
          plugin: 'flutter_image_compress',
          code: 'image-compress-failed',
          message: 'Unable to process a selected attachment.',
        );
      }
      final uploadBytes = Uint8List.fromList(compressedBytes);
      if (uploadBytes.length > 5 * 1024 * 1024) {
        throw FirebaseException(
          plugin: 'firebase_storage',
          code: 'file-too-large',
          message: 'Each processed attachment must be 5 MB or smaller.',
        );
      }

      final attachmentId =
          '${DateTime.now().millisecondsSinceEpoch}_${index + 1}';
      final storagePath = 'supportTickets/$uid/$ticketId/$attachmentId.jpg';
      final ref = _storage.ref().child(storagePath);
      await ref.putData(
        uploadBytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'ticketId': ticketId,
            'originalFileName': attachment.fileName.trim(),
          },
        ),
      );

      uploaded.add(
        SupportUploadedTicketAttachment(
          attachmentId: attachmentId,
          storagePath: storagePath,
          fileName: attachment.fileName.trim().isEmpty
              ? 'attachment.jpg'
              : attachment.fileName.trim(),
          contentType: 'image/jpeg',
        ),
      );
    }
    return uploaded;
  }

  Future<void> cleanupUploadedAttachments(
    List<SupportUploadedTicketAttachment> attachments,
  ) async {
    for (final attachment in attachments) {
      try {
        await _storage.ref().child(attachment.storagePath).delete();
      } on FirebaseException {
        // Best-effort cleanup only.
      } catch (_) {
        // Best-effort cleanup only.
      }
    }
  }

  Future<String> getAttachmentDownloadUrl(String storagePath) async {
    return _storage.ref().child(storagePath.trim()).getDownloadURL();
  }

  Future<void> replyToTicket({
    required String ticketId,
    required String message,
  }) async {
    final callable = _functions.httpsCallable('replyToSupportTicket');
    await callable.call<Map<String, dynamic>>({
      'ticketId': ticketId.trim(),
      'message': message.trim(),
    });
  }

  Future<void> markTicketRead(String ticketId) async {
    final callable = _functions.httpsCallable('markSupportTicketRead');
    await callable.call<Map<String, dynamic>>({'ticketId': ticketId.trim()});
  }
}
