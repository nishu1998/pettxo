import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../domain/models/pet_profile.dart';

class PetRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  PetRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> _petsCollection(String ownerId) {
    return _firestore.collection('users').doc(ownerId).collection('pets');
  }

  String get _currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw Exception('User not authenticated');
    }
    return uid;
  }

  Stream<List<PetProfile>> watchVisiblePets(String ownerId) {
    final trimmedOwnerId = ownerId.trim();
    if (trimmedOwnerId.isEmpty) return Stream.value(const <PetProfile>[]);

    return _petsCollection(
      trimmedOwnerId,
    ).where('isDeleted', isEqualTo: false).snapshots().map((snapshot) {
      final pets = snapshot.docs
          .map(PetProfile.fromDocument)
          .where((pet) => !pet.isDeleted)
          .toList(growable: false);
      pets.sort((a, b) {
        final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
        return aTime.compareTo(bTime);
      });
      return pets;
    });
  }

  Stream<PetProfile?> watchPet({
    required String ownerId,
    required String petId,
  }) {
    final trimmedOwnerId = ownerId.trim();
    final trimmedPetId = petId.trim();
    if (trimmedOwnerId.isEmpty || trimmedPetId.isEmpty) {
      return Stream.value(null);
    }

    return _petsCollection(trimmedOwnerId).doc(trimmedPetId).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return null;
      final pet = PetProfile.fromDocument(snapshot);
      return pet.isDeleted ? null : pet;
    });
  }

  Future<String> createPet({required PetProfile pet, File? photoFile}) async {
    final ownerId = _currentUid;
    if (pet.ownerId != ownerId) {
      throw Exception('Pet owner does not match current user');
    }

    final document = _petsCollection(ownerId).doc();
    final photoUrl = photoFile == null
        ? pet.photoUrl
        : await uploadPetPhoto(
            ownerId: ownerId,
            petId: document.id,
            photoFile: photoFile,
          );

    final petToSave = pet.copyWith(id: document.id, photoUrl: photoUrl);
    await document.set(
      petToSave.toSaveMap(
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      ),
    );
    return document.id;
  }

  Future<void> updatePet({required PetProfile pet, File? photoFile}) async {
    final ownerId = _currentUid;
    if (pet.ownerId != ownerId) {
      throw Exception('Pet owner does not match current user');
    }

    final photoUrl = photoFile == null
        ? pet.photoUrl
        : await uploadPetPhoto(
            ownerId: ownerId,
            petId: pet.id,
            photoFile: photoFile,
          );

    await _petsCollection(ownerId)
        .doc(pet.id)
        .set(
          pet
              .copyWith(photoUrl: photoUrl)
              .toSaveMap(
                createdAt: pet.createdAt == null
                    ? FieldValue.serverTimestamp()
                    : Timestamp.fromDate(pet.createdAt!),
                updatedAt: FieldValue.serverTimestamp(),
              ),
          SetOptions(merge: true),
        );
  }

  Future<void> softDeletePet({
    required String ownerId,
    required String petId,
  }) async {
    final currentUid = _currentUid;
    if (ownerId != currentUid) {
      throw Exception('Only the owner can delete this pet');
    }

    await _petsCollection(ownerId).doc(petId).set({
      'isDeleted': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'deletedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> uploadPetPhoto({
    required String ownerId,
    required String petId,
    required File photoFile,
  }) async {
    final currentUid = _currentUid;
    if (ownerId != currentUid) {
      throw Exception('Only the owner can upload this pet photo');
    }

    final bytes = await _preparePetPhotoBytes(photoFile);
    final ref = _storage.ref().child(
      'users/$ownerId/pets/$petId/photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<Uint8List> _preparePetPhotoBytes(File photo) async {
    final originalBytes = await photo.readAsBytes();
    final compressedBytes = await FlutterImageCompress.compressWithList(
      originalBytes,
      quality: 84,
      minWidth: 1400,
      minHeight: 1400,
      format: CompressFormat.jpeg,
    );

    if (compressedBytes.isEmpty) {
      return Uint8List.fromList(originalBytes);
    }
    return Uint8List.fromList(compressedBytes);
  }
}
