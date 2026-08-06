import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../../../../core/services/firestore_cache_service.dart';
import '../../../profile/data/repositories/profile_repository.dart';
import '../../../profile/domain/models/profile_service_listing.dart';
import '../../domain/models/service_model.dart';

class ServicesRepository {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final ProfileRepository _profileRepository = ProfileRepository();
  final Map<String, bool> _ownerVisibilityCache = <String, bool>{};

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
    return _activeServicesQuery(limit: limit).snapshots().asyncMap(
      (snapshot) => _filterServicesByVisibleOwners(_mapSnapshot(snapshot)),
    );
  }

  Stream<List<ServiceModel>> watchActiveServicesByCategory(
    String category, {
    int limit = 30,
  }) {
    return _activeServicesQuery(limit: limit)
        .where('categoryLowercase', isEqualTo: category.trim().toLowerCase())
        .snapshots()
        .asyncMap(
          (snapshot) => _filterServicesByVisibleOwners(_mapSnapshot(snapshot)),
        );
  }

  Stream<List<ServiceModel>> watchActiveServicesFiltered({
    String? category,
    int limit = 30,
  }) {
    Query<Map<String, dynamic>> query = _activeServicesQuery(limit: limit);

    final normalizedCategory = category?.trim().toLowerCase() ?? '';

    if (normalizedCategory.isNotEmpty) {
      query = query.where('categoryLowercase', isEqualTo: normalizedCategory);
    }

    return query.snapshots().asyncMap(
      (snapshot) => _filterServicesByVisibleOwners(_mapSnapshot(snapshot)),
    );
  }

  Stream<List<ServiceModel>> watchActiveServicesByCity(
    String city, {
    int limit = 30,
  }) {
    return _activeServicesQuery(limit: limit)
        .where('location.city', isEqualTo: city.trim())
        .snapshots()
        .asyncMap(
          (snapshot) => _filterServicesByVisibleOwners(_mapSnapshot(snapshot)),
        );
  }

  Stream<List<ServiceModel>> watchOwnerServices(String ownerUserId) {
    return _services
        .where('ownerUserId', isEqualTo: ownerUserId)
        .where('isDeleted', isEqualTo: false)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(ServiceModel.fromDocument).toList(),
        );
  }

  Stream<List<ServiceModel>> watchPublicOwnerServices(String ownerUserId) {
    return _services
        .where('ownerUserId', isEqualTo: ownerUserId)
        .where('isDeleted', isEqualTo: false)
        .where('isVisibleToMarketplace', isEqualTo: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final services = await _filterServicesByVisibleOwners(
            _mapSnapshot(snapshot),
          );
          services.sort((a, b) {
            final aTime =
                a.updatedAt?.millisecondsSinceEpoch ??
                a.createdAt?.millisecondsSinceEpoch ??
                0;
            final bTime =
                b.updatedAt?.millisecondsSinceEpoch ??
                b.createdAt?.millisecondsSinceEpoch ??
                0;
            return bTime.compareTo(aTime);
          });
          return services;
        });
  }

  Future<ServiceModel?> fetchServiceById(String serviceId) async {
    final id = serviceId.trim();
    if (id.isEmpty) return null;

    final snapshot = await FirestoreCacheService.getDocCacheFirst(
      _services.doc(id),
    );
    if (!snapshot.exists) return null;
    final service = ServiceModel.fromDocument(snapshot);
    if (!_isServicePubliclyVisible(service)) return null;
    return await _isOwnerVisible(service.ownerUserId) ? service : null;
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

    final snapshot = await FirestoreCacheService.getCollectionCacheFirst(query);
    final docs = snapshot.docs;
    final services = await _filterServicesByVisibleOwners(
      docs
          .map(ServiceModel.fromDocument)
          .where((service) => !service.isEffectivelyPausedByVerification)
          .toList(),
    );

    return ServicesPage(
      services: services,
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
      schedulingMode: service.schedulingMode,
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
      providerVerificationStatus: service.providerVerificationStatus,
      providerVerificationGraceEndsAt: service.providerVerificationGraceEndsAt,
      isPausedByVerification: service.isPausedByVerification,
      pauseReason: service.pauseReason,
      ratingAverage: service.ratingAverage,
      ratingCount: service.ratingCount,
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
    return snapshot.docs
        .map(ServiceModel.fromDocument)
        .where((service) => !service.isEffectivelyPausedByVerification)
        .toList();
  }

  bool _isServicePubliclyVisible(ServiceModel service) {
    return !service.isDeleted &&
        service.isActive &&
        !service.isPaused &&
        service.isVisibleToMarketplace;
  }

  Future<List<ServiceModel>> _filterServicesByVisibleOwners(
    List<ServiceModel> services,
  ) async {
    if (services.isEmpty) return const <ServiceModel>[];

    final missingOwnerIds = services
        .map((service) => service.ownerUserId.trim())
        .where((ownerId) => ownerId.isNotEmpty)
        .where((ownerId) => !_ownerVisibilityCache.containsKey(ownerId))
        .toSet()
        .toList(growable: false);

    if (missingOwnerIds.isNotEmpty) {
      final fetchedVisibility = await _profileRepository
          .fetchPublicVisibilityByIds(missingOwnerIds);
      _ownerVisibilityCache.addAll(fetchedVisibility);
    }

    return services
        .where((service) {
          final ownerId = service.ownerUserId.trim();
          if (ownerId.isEmpty) return false;
          if (!_isServicePubliclyVisible(service)) return false;
          return _ownerVisibilityCache[ownerId] ?? false;
        })
        .toList(growable: false);
  }

  Future<bool> _isOwnerVisible(String ownerUserId) async {
    final trimmedOwnerId = ownerUserId.trim();
    if (trimmedOwnerId.isEmpty) return false;

    final cached = _ownerVisibilityCache[trimmedOwnerId];
    if (cached != null) {
      return cached;
    }

    final fetchedVisibility = await _profileRepository
        .fetchPublicVisibilityByIds([trimmedOwnerId]);
    final resolved = fetchedVisibility[trimmedOwnerId] ?? false;
    _ownerVisibilityCache[trimmedOwnerId] = resolved;
    return resolved;
  }

  Future<List<String>> _uploadServicePhotos({
    required String ownerUserId,
    required String serviceId,
    required List<File> photos,
  }) async {
    final urls = <String>[];

    for (var index = 0; index < photos.length; index++) {
      final photo = photos[index];
      final uploadBytes = await _prepareServicePhotoBytes(photo);
      final ref = _storage.ref().child(
        'users/$ownerUserId/services/$serviceId/photo_$index.jpg',
      );

      await ref.putData(
        uploadBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      urls.add(await ref.getDownloadURL());
    }

    return urls;
  }

  Future<Uint8List> _prepareServicePhotoBytes(File photo) async {
    final originalBytes = await photo.readAsBytes();
    final compressedBytes = await FlutterImageCompress.compressWithList(
      originalBytes,
      quality: 84,
      minWidth: 1600,
      minHeight: 1600,
      format: CompressFormat.jpeg,
    );

    if (compressedBytes.isEmpty) {
      return Uint8List.fromList(originalBytes);
    }

    return Uint8List.fromList(compressedBytes);
  }
}

extension ServiceProfileAdapter on Iterable<ServiceModel> {
  List<ProfileServiceListing> toProfileListings() {
    return map((service) => service.toProfileListing()).toList();
  }
}
