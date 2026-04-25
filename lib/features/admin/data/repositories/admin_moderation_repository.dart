import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/moderation_item.dart';

class AdminModerationRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  AdminModerationRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _queue =>
      _firestore.collection('moderationQueue');

  CollectionReference<Map<String, dynamic>> get _auditLogs =>
      _firestore.collection('adminAuditLogs');

  CollectionReference<Map<String, dynamic>> get _services =>
      _firestore.collection('services');

  String get _adminUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('Admin not authenticated');
    }
    return uid;
  }

  Stream<List<ModerationItem>> watchPendingItems({int limit = 50}) {
    return _queue
        .where('status', isEqualTo: 'pending')
        .orderBy('severity', descending: true)
        .orderBy('createdAt')
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map(ModerationItem.fromDocument).toList();
        });
  }

  Future<void> approveService({
    required String serviceId,
    required String moderationItemId,
    String reason = 'Approved by admin',
  }) async {
    final adminUid = _adminUid;
    final batch = _firestore.batch();
    final serviceRef = _services.doc(serviceId);
    final queueRef = _queue.doc(moderationItemId);
    final auditRef = _auditLogs.doc();

    batch.set(serviceRef, {
      'moderationStatus': 'approved',
      'isVisibleToMarketplace': true,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(queueRef, {
      'status': 'approved',
      'assignedAdminId': adminUid,
      'reason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'resolvedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(auditRef, {
      'adminId': adminUid,
      'action': 'service.approve',
      'targetType': 'service',
      'targetId': serviceId,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> removeService({
    required String serviceId,
    required String moderationItemId,
    required String reason,
  }) async {
    final adminUid = _adminUid;
    final batch = _firestore.batch();
    final serviceRef = _services.doc(serviceId);
    final queueRef = _queue.doc(moderationItemId);
    final auditRef = _auditLogs.doc();

    batch.set(serviceRef, {
      'moderationStatus': 'removed',
      'isVisibleToMarketplace': false,
      'isActive': false,
      'status': 'removed',
      'moderationReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'removedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(queueRef, {
      'status': 'removed',
      'assignedAdminId': adminUid,
      'reason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
      'resolvedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(auditRef, {
      'adminId': adminUid,
      'action': 'service.remove',
      'targetType': 'service',
      'targetId': serviceId,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
}
