import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/claimed_offer.dart';
import '../../domain/models/mobile_offer_campaign.dart';
import '../../domain/models/offer_types.dart';

class OfferService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  OfferService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  Future<EligibleOffersResult> getEligibleOffers({
    String? screen,
    String? serviceCategory,
    double? bookingAmount,
  }) async {
    final callable = _functions.httpsCallable('getEligibleOffers');
    final result = await callable.call<Map<String, dynamic>>({
      'context': {
        'screen': screen,
        'serviceCategory': serviceCategory,
        'bookingAmount': bookingAmount,
      },
    });

    final data = result.data;
    if (data['ok'] != true) {
      return EligibleOffersResult.empty;
    }

    return EligibleOffersResult.fromMap(data);
  }

  Future<String> claimOffer({
    required String campaignId,
    required OfferDisplayType sourceDisplayType,
  }) async {
    final callable = _functions.httpsCallable('claimOffer');
    final result = await callable.call<Map<String, dynamic>>({
      'campaignId': campaignId.trim(),
      'sourceDisplayType': sourceDisplayType.value,
    });

    return (result.data['claimedOfferId'] as String? ?? '').trim();
  }

  Future<OfferPreviewResult> previewOfferForBooking({
    required String claimedOfferId,
    required double bookingAmount,
    String? serviceId,
    String? category,
  }) async {
    final callable = _functions.httpsCallable('previewOfferForBooking');
    final result = await callable.call<Map<String, dynamic>>({
      'claimedOfferId': claimedOfferId.trim(),
      'bookingAmount': bookingAmount,
      'serviceId': serviceId,
      'category': category,
    });

    return OfferPreviewResult.fromMap(result.data);
  }

  Stream<List<ClaimedOffer>> watchClaimedOffers() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('claimedOffers')
        .snapshots()
        .map((snapshot) {
          final offers = snapshot.docs.map(ClaimedOffer.fromDocument).toList();
          offers.sort((left, right) {
            final leftTime = left.claimedAt?.millisecondsSinceEpoch ?? 0;
            final rightTime = right.claimedAt?.millisecondsSinceEpoch ?? 0;
            return rightTime.compareTo(leftTime);
          });
          return offers;
        });
  }

  Future<bool> shouldShowOffer(String offerId) async {
    final prefs = await SharedPreferences.getInstance();
    final dismissCount = prefs.getInt(_dismissCountKey(offerId)) ?? 0;
    if (dismissCount >= 2) return false;

    final lastShownAtMs = prefs.getInt(_lastShownAtKey(offerId));
    if (lastShownAtMs == null) return true;

    final lastShownAt = DateTime.fromMillisecondsSinceEpoch(lastShownAtMs);
    final now = DateTime.now();
    return !_isSameDay(lastShownAt, now);
  }

  Future<void> markOfferShown(String offerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _lastShownAtKey(offerId),
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> recordOfferDismissed(String offerId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_dismissCountKey(offerId)) ?? 0;
    await prefs.setInt(_dismissCountKey(offerId), current + 1);
  }

  Future<void> resetOfferDismissal(String offerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dismissCountKey(offerId));
  }

  String _lastShownAtKey(String offerId) => 'offers.lastShownAt.$offerId';

  String _dismissCountKey(String offerId) => 'offers.dismissCount.$offerId';

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class OfferPreviewResult {
  final bool ok;
  final bool isValid;
  final double discountAmount;
  final double finalAmount;
  final String message;
  final String claimedOfferId;
  final String campaignId;

  const OfferPreviewResult({
    required this.ok,
    required this.isValid,
    required this.discountAmount,
    required this.finalAmount,
    required this.message,
    required this.claimedOfferId,
    required this.campaignId,
  });

  factory OfferPreviewResult.fromMap(Map<String, dynamic> data) {
    return OfferPreviewResult(
      ok: data['ok'] == true,
      isValid: data['isValid'] == true,
      discountAmount: (data['discountAmount'] as num?)?.toDouble() ?? 0,
      finalAmount: (data['finalAmount'] as num?)?.toDouble() ?? 0,
      message: (data['message'] as String? ?? '').trim(),
      claimedOfferId: (data['claimedOfferId'] as String? ?? '').trim(),
      campaignId: (data['campaignId'] as String? ?? '').trim(),
    );
  }
}
