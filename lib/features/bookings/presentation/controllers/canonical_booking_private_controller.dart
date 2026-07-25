import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/models/canonical_booking_private.dart';

@immutable
class CanonicalBookingPrivateState {
  const CanonicalBookingPrivateState({
    required this.bookingId,
    required this.isLoading,
    required this.privateData,
    required this.errorMessage,
  });

  const CanonicalBookingPrivateState.initial()
    : bookingId = '',
      isLoading = false,
      privateData = null,
      errorMessage = null;

  final String bookingId;
  final bool isLoading;
  final CanonicalBookingPrivateData? privateData;
  final String? errorMessage;

  bool get hasData => privateData != null;

  CanonicalBookingPrivateState copyWith({
    String? bookingId,
    bool? isLoading,
    CanonicalBookingPrivateData? privateData,
    bool clearPrivateData = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CanonicalBookingPrivateState(
      bookingId: bookingId ?? this.bookingId,
      isLoading: isLoading ?? this.isLoading,
      privateData: clearPrivateData ? null : (privateData ?? this.privateData),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

typedef CanonicalBookingPrivateStreamLoader =
    Stream<CanonicalBookingPrivateData?> Function(String bookingId);
typedef CanonicalBookingPrivateAuthStateStreamFactory =
    Stream<Object?> Function();

class CanonicalBookingPrivateController extends ChangeNotifier {
  CanonicalBookingPrivateController({
    required CanonicalBookingPrivateStreamLoader privateLoader,
    CanonicalBookingPrivateAuthStateStreamFactory? authStateStreamFactory,
  }) : _privateLoader = privateLoader,
       _authStateStreamFactory = authStateStreamFactory;

  final CanonicalBookingPrivateStreamLoader _privateLoader;
  final CanonicalBookingPrivateAuthStateStreamFactory? _authStateStreamFactory;

  StreamSubscription<CanonicalBookingPrivateData?>? _privateSubscription;
  StreamSubscription<Object?>? _authSubscription;
  CanonicalBookingPrivateState _state =
      const CanonicalBookingPrivateState.initial();
  String _activeBookingId = '';
  bool _activeReadPermission = false;

  CanonicalBookingPrivateState get state => _state;

  void bind({required String bookingId, required bool shouldLoadPrivate}) {
    final safeBookingId = bookingId.trim();
    _ensureAuthSubscription();

    if (safeBookingId.isEmpty) {
      clear();
      return;
    }

    if (!shouldLoadPrivate) {
      _cancelPrivateSubscription();
      _activeBookingId = safeBookingId;
      _activeReadPermission = false;
      _setState(
        CanonicalBookingPrivateState(
          bookingId: safeBookingId,
          isLoading: false,
          privateData: null,
          errorMessage: null,
        ),
      );
      return;
    }

    if (_activeReadPermission && _activeBookingId == safeBookingId) {
      return;
    }

    _cancelPrivateSubscription();
    _activeBookingId = safeBookingId;
    _activeReadPermission = true;
    _setState(
      CanonicalBookingPrivateState(
        bookingId: safeBookingId,
        isLoading: true,
        privateData: null,
        errorMessage: null,
      ),
    );

    _privateSubscription = _privateLoader(safeBookingId).listen(
      (privateData) {
        _setState(
          CanonicalBookingPrivateState(
            bookingId: safeBookingId,
            isLoading: false,
            privateData: privateData,
            errorMessage: null,
          ),
        );
      },
      onError: (error, stackTrace) {
        _setState(
          CanonicalBookingPrivateState(
            bookingId: safeBookingId,
            isLoading: false,
            privateData: null,
            errorMessage:
                'Paid-only booking details could not be loaded right now.',
          ),
        );
      },
    );
  }

  void clear() {
    _cancelPrivateSubscription();
    _activeBookingId = '';
    _activeReadPermission = false;
    _setState(const CanonicalBookingPrivateState.initial());
  }

  void _ensureAuthSubscription() {
    if (_authSubscription != null || _authStateStreamFactory == null) {
      return;
    }
    _authSubscription = _authStateStreamFactory().listen((user) {
      if (user == null) {
        clear();
      }
    });
  }

  void _cancelPrivateSubscription() {
    _privateSubscription?.cancel();
    _privateSubscription = null;
  }

  void _setState(CanonicalBookingPrivateState nextState) {
    if (_state == nextState) return;
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelPrivateSubscription();
    _authSubscription?.cancel();
    super.dispose();
  }
}
