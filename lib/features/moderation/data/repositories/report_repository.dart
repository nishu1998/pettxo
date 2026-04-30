import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ReportRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ReportRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  Future<String> createReport({
    required String type,
    required String targetId,
    required String reason,
    String? description,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }

    final normalizedType = type.trim().toLowerCase();
    final normalizedTargetId = targetId.trim();
    final normalizedReason = reason.trim();
    final normalizedDescription = description?.trim() ?? '';

    if (normalizedType.isEmpty) {
      throw ArgumentError.value(type, 'type', 'type is required');
    }
    if (normalizedTargetId.isEmpty) {
      throw ArgumentError.value(targetId, 'targetId', 'targetId is required');
    }
    if (normalizedReason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'reason is required');
    }

    final profileSnapshot = await _firestore.collection('users').doc(uid).get();
    final profileData = profileSnapshot.data() ?? const <String, dynamic>{};
    final reporterName = _resolveReporterName(profileData);

    final doc = _firestore.collection('reports').doc();
    await doc.set({
      'type': normalizedType,
      'targetId': normalizedTargetId,
      'reportedBy': uid,
      'reporterName': reporterName,
      'reason': normalizedReason,
      'description': normalizedDescription,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  String _resolveReporterName(Map<String, dynamic> data) {
    final name = (data['name'] as String? ?? '').trim();
    if (name.isNotEmpty) return name;
    final username = (data['username'] as String? ?? '').trim().replaceFirst(
      '@',
      '',
    );
    if (username.isNotEmpty) return username;
    return 'Pettxo user';
  }
}
