import 'package:cloud_functions/cloud_functions.dart';

import '../../../../core/services/firebase_resilience_service.dart';
import '../../domain/models/available_offer.dart';

class OfferService {
  final FirebaseFunctions _functions;

  OfferService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  Future<AvailableOffersResult> getAvailableOffers({
    String? screen,
    String? serviceCategory,
    double? bookingAmount,
    String? serviceId,
    String? providerId,
  }) async {
    final data =
        await FirebaseResilienceService.retryTransient<Map<String, dynamic>>(
          operationName: 'offers.getAvailableOffers',
          operation: () async {
            final callable = _functions.httpsCallable('getAvailableOffers');
            final result = await callable.call<dynamic>({
              'context': {
                'screen': screen,
                'serviceCategory': serviceCategory,
                'bookingAmount': bookingAmount,
                'serviceId': serviceId,
                'providerId': providerId,
              },
            });
            final rawData = result.data;
            if (rawData is! Map) {
              return const <String, dynamic>{'ok': false};
            }
            return Map<String, dynamic>.from(rawData);
          },
        );

    if (data['ok'] != true) {
      return AvailableOffersResult.empty;
    }

    return AvailableOffersResult.fromMap(data);
  }
}
