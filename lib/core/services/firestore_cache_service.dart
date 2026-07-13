import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'network_status_service.dart';

class FirestoreCacheService {
  const FirestoreCacheService._();

  static Future<DocumentSnapshot<Map<String, dynamic>>> getDocCacheFirst(
    DocumentReference<Map<String, dynamic>> reference, {
    Duration serverTimeout = const Duration(seconds: 4),
  }) async {
    try {
      final cacheSnapshot = await reference.get(
        const GetOptions(source: Source.cache),
      );
      if (cacheSnapshot.exists) {
        debugPrint(
          'FirestoreCacheService debug -> cache hit for doc=${reference.path}',
        );
        return cacheSnapshot;
      }
      debugPrint(
        'FirestoreCacheService debug -> cache miss for doc=${reference.path}',
      );
      if (NetworkStatusService.instance.isOffline) {
        return cacheSnapshot;
      }
    } catch (error) {
      debugPrint(
        'FirestoreCacheService debug -> cache read failed for doc=${reference.path}: $error',
      );
      if (NetworkStatusService.instance.isOffline) rethrow;
    }

    final serverSnapshot = await reference.get().timeout(serverTimeout);
    debugPrint(
      'FirestoreCacheService debug -> server read completed for doc=${reference.path}',
    );
    return serverSnapshot;
  }

  static Future<QuerySnapshot<Map<String, dynamic>>> getCollectionCacheFirst(
    Query<Map<String, dynamic>> query, {
    Duration serverTimeout = const Duration(seconds: 4),
  }) async {
    try {
      final cacheSnapshot = await query.get(
        const GetOptions(source: Source.cache),
      );
      if (cacheSnapshot.docs.isNotEmpty) {
        debugPrint(
          'FirestoreCacheService debug -> cache hit for query=${query.runtimeType}',
        );
        return cacheSnapshot;
      }
      debugPrint(
        'FirestoreCacheService debug -> cache miss for query=${query.runtimeType}',
      );
      if (NetworkStatusService.instance.isOffline) {
        return cacheSnapshot;
      }
    } catch (error) {
      debugPrint(
        'FirestoreCacheService debug -> cache read failed for query=${query.runtimeType}: $error',
      );
      if (NetworkStatusService.instance.isOffline) rethrow;
    }

    final serverSnapshot = await query.get().timeout(serverTimeout);
    debugPrint(
      'FirestoreCacheService debug -> server read completed for query=${query.runtimeType}',
    );
    return serverSnapshot;
  }
}
