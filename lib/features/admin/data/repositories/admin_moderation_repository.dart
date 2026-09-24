import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/moderation_item.dart';

class AdminModerationRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  AdminModerationRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  CollectionReference<Map<String, dynamic>> get _queue =>
      _firestore.collection('moderationQueue');

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
    _adminUid;
    await _functions.httpsCallable('moderateService').call<void>({
      'serviceId': serviceId,
      'moderationItemId': moderationItemId,
      'action': 'approve',
      'reason': reason,
    });
  }

  Future<void> removeService({
    required String serviceId,
    required String moderationItemId,
    required String reason,
  }) async {
    _adminUid;
    await _functions.httpsCallable('moderateService').call<void>({
      'serviceId': serviceId,
      'moderationItemId': moderationItemId,
      'action': 'remove',
      'reason': reason,
    });
  }
}
