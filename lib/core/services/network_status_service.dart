import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class NetworkStatusService {
  NetworkStatusService._();

  static final NetworkStatusService instance = NetworkStatusService._();

  final Connectivity _connectivity = Connectivity();
  final ValueNotifier<bool> _isOnlineNotifier = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _initialized = false;

  ValueListenable<bool> get isOnlineListenable => _isOnlineNotifier;

  bool get isOnline => _isOnlineNotifier.value;

  bool get isOffline => !_isOnlineNotifier.value;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results, reason: 'initial-check');
    } catch (error) {
      debugPrint(
        'NetworkStatusService initialize debug -> connectivity check failed: $error',
      );
    }

    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) => _updateStatus(results, reason: 'connectivity-change'),
      onError: (Object error) {
        debugPrint(
          'NetworkStatusService listener debug -> connectivity stream failed: $error',
        );
      },
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }

  void _updateStatus(List<ConnectivityResult> results, {required String reason}) {
    final nextOnline = results.any((result) => result != ConnectivityResult.none);
    final previousOnline = _isOnlineNotifier.value;
    _isOnlineNotifier.value = nextOnline;

    if (previousOnline != nextOnline) {
      debugPrint(
        'NetworkStatusService status debug -> online=$nextOnline, reason=$reason, results=$results',
      );
    }
  }
}
