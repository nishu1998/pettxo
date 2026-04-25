import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/moderation_report.dart';

class ModerationRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  ModerationRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  Future<String> createReport(ModerationReport report) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }
    if (report.reporterId != uid) {
      throw Exception('Reporter does not match current user');
    }

    final doc = _firestore.collection('reports').doc();
    await doc.set(report.toCreateMap());
    return doc.id;
  }
}
