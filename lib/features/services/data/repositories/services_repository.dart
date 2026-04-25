import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../../profile/domain/models/profile_service_listing.dart';
import '../../domain/models/service_model.dart';

class ServicesRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  ServicesRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _services =>
      _firestore.collection('services');

  String get _currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw Exception('User not authenticated');
    }
    return uid;
  }

  Stream<List<ServiceModel>> watchActiveServices({int limit = 30}) {
    return _activeServicesQuery(limit: limit).snapshots().map(_mapSnapshot);
  }

  Stream<List<ServiceModel>> watchActiveServicesByCategory(
    String category, {
    int limit = 30,
  }) {
    return _activeServicesQuery(limit: limit)
        .where('categoryLowercase', isEqualTo: category.trim().toLowerCase())
        .snapshots()
        .map(_mapSnapshot);
  }

  Stream<List<ServiceModel>> watchActiveServicesByCity(
    String city, {
    int limit = 30,
  }) {
    return _activeServicesQuery(limit: limit)
        .where('location.city', isEqualTo: city.trim())
        .snapshots()
        .map(_mapSnapshot);
  }

  Stream<List<ServiceModel>> watchOwnerServices(String ownerUserId) {
    return _services
        .where('ownerUserId', isEqualTo: ownerUserId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(_mapSnapshot);
  }

  Future<ServicesPage> fetchActiveServicesPage({
    int limit = 20,
    String? category,
    String? city,
    DocumentSnapshot<Map<String, dynamic>>? startAfterDocument,
  }) async {
    Query<Map<String, dynamic>> query = _activeServicesQuery(limit: limit);

    if (category != null && category.trim().isNotEmpty) {
      query = query.where(
        'categoryLowercase',
        isEqualTo: category.trim().toLowerCase(),
      );
    }

    if (city != null && city.trim().isNotEmpty) {
      query = query.where('location.city', isEqualTo: city.trim());
    }

    if (startAfterDocument != null) {
      query = query.startAfterDocument(startAfterDocument);
    }

    final snapshot = await query.get();
    final docs = snapshot.docs;

    return ServicesPage(
      services: docs.map(ServiceModel.fromDocument).toList(),
      lastDocument: docs.isEmpty ? null : docs.last,
      hasMore: docs.length == limit,
    );
  }

  Future<String> createService({
    required ServiceModel service,
    required List<File> photos,
  }) async {
    final uid = _currentUid;
    if (service.ownerUserId != uid) {
      throw Exception('Service owner does not match current user');
    }

    final doc = _services.doc();
    final photoUrls = await _uploadServicePhotos(
      ownerUserId: uid,
      serviceId: doc.id,
      photos: photos,
    );

    final serviceWithUploadedPhotos = ServiceModel(
      id: doc.id,
      ownerUserId: service.ownerUserId,
      ownerName: service.ownerName,
      ownerUsername: service.ownerUsername,
      ownerPhotoUrl: service.ownerPhotoUrl,
      ownerCity: service.ownerCity,
      ownerState: service.ownerState,
      title: service.title,
      animalType: service.animalType,
      category: service.category,
      description: service.description,
      privateNotes: service.privateNotes,
      pricePerSession: service.pricePerSession,
      currency: service.currency,
      sessionDurationMinutes: service.sessionDurationMinutes,
      capacity: service.capacity,
      availableDays: service.availableDays,
      startMinutes: service.startMinutes,
      endMinutes: service.endMinutes,
      sameForAllDays: service.sameForAllDays,
      serviceType: service.serviceType,
      displayAddress: service.displayAddress,
      latitude: service.latitude,
      longitude: service.longitude,
      city: service.city,
      state: service.state,
      photoUrls: photoUrls,
      primaryPhotoUrl: photoUrls.isEmpty ? '' : photoUrls.first,
      status: service.status,
      isActive: service.isActive,
      isDeleted: service.isDeleted,
      isPaused: service.isPaused,
      moderationStatus: service.moderationStatus,
      isVisibleToMarketplace: service.isVisibleToMarketplace,
      createdAt: service.createdAt,
      updatedAt: service.updatedAt,
      publishedAt: service.publishedAt,
    );

    await doc.set(serviceWithUploadedPhotos.toCreateMap());
    return doc.id;
  }

  Future<void> setServicePaused(String serviceId, bool isPaused) async {
    await _services.doc(serviceId).set({
      'isPaused': isPaused,
      'status': isPaused ? 'paused' : 'active',
      'isActive': !isPaused,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteService(String serviceId) async {
    await _services.doc(serviceId).set({
      'isDeleted': true,
      'isActive': false,
      'isVisibleToMarketplace': false,
      'status': 'removed',
      'updatedAt': FieldValue.serverTimestamp(),
      'removedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> pauseAllServicesForOwner(String ownerUserId) async {
    final snapshot = await _services
        .where('ownerUserId', isEqualTo: ownerUserId)
        .where('isDeleted', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.set(doc.reference, {
        'isPaused': true,
        'isActive': false,
        'status': 'paused',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Query<Map<String, dynamic>> _activeServicesQuery({required int limit}) {
    return _services
        .where('status', isEqualTo: 'active')
        .where('isActive', isEqualTo: true)
        .where('isDeleted', isEqualTo: false)
        .where('isPaused', isEqualTo: false)
        .where('isVisibleToMarketplace', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit);
  }

  List<ServiceModel> _mapSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    return snapshot.docs.map(ServiceModel.fromDocument).toList();
  }

  Future<List<String>> _uploadServicePhotos({
    required String ownerUserId,
    required String serviceId,
    required List<File> photos,
  }) async {
    final urls = <String>[];

    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      final extension = photo.path.split('.').last.toLowerCase();
      final ref = _storage.ref().child(
        'users/$ownerUserId/services/$serviceId/photo_$index.$extension',
      );

      await ref.putFile(photo);
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }
}

extension ServiceProfileAdapter on Iterable<ServiceModel> {
  List<ProfileServiceListing> toProfileListings() {
    return map((service) => service.toProfileListing()).toList();
  }
}
