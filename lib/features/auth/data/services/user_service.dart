import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> createUserProfile({
    required String role,
    required String name,
    required String username,
    required String phone,
    required String state,
    required String city,
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
      "username": _normalizeUsername(username),
      "usernameLowercase": _normalizeUsername(username),
      "phone": phone.trim(),
      "state": state.trim(),
      "city": city.trim(),
      "profileImage": "",
      "bio": "",
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  Future<DocumentSnapshot?> getUserProfile() async {
    final user = _auth.currentUser;

    if (user == null) {
      return null;
    }

    return _firestore.collection("users").doc(user.uid).get();
  }

  Future<bool> hasUserProfile() async {
    final user = _auth.currentUser;

    if (user == null) {
      return false;
    }

    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    return snapshot.exists && snapshot.data() != null;
  }

  Future<String> getPostAuthRoute() async {
    return await hasUserProfile() ? '/home' : '/profile-type';
  }

  Future<void> updateProfile(Map<String, dynamic> data) async {
    final uid = _auth.currentUser!.uid;

    final updatedData = {...data};
    final username = updatedData['username'] as String?;
    if (username != null) {
      updatedData['username'] = _normalizeUsername(username);
      updatedData['usernameLowercase'] = _normalizeUsername(username);
    }

    await _firestore
        .collection("users")
        .doc(uid)
        .set(updatedData, SetOptions(merge: true));
  }

  String _normalizeUsername(String username) {
    return username.trim().replaceAll('@', '').toLowerCase();
  }
}
