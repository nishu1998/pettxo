import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// CREATE USER PROFILE AFTER SIGNUP FLOW
  Future<void> createUserProfile({
    required String role,
    required String name,
    required String username,
    required String location,
  }) async {

    final user = _auth.currentUser;

    if (user == null) {
      throw Exception("User not authenticated");
    }

    await _firestore.collection('users').doc(user.uid).set({

      "uid": user.uid,
      "email": user.email,
      "role": role,

      "name": name,
      "username": username,
      "location": location,

      "profileImage": "",
      "bio": "",

      "createdAt": FieldValue.serverTimestamp(),

    });

  }

  /// FETCH USER PROFILE
Future<DocumentSnapshot?> getUserProfile() async {

  final user = _auth.currentUser;

  if (user == null) {
    return null;
  }

  return await _firestore.collection("users").doc(user.uid).get();
}

  /// UPDATE USER PROFILE
  Future<void> updateProfile(Map<String, dynamic> data) async {

    final uid = _auth.currentUser!.uid;

    await _firestore
    .collection("users")
    .doc(uid)
    .set(data, SetOptions(merge: true));

  }

}