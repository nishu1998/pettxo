import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/services/firebase_resilience_service.dart';
import '../../domain/models/offer_wall_campaign_payload.dart';

class OfferWallService {
  OfferWallService({FirebaseFunctions? functions}) : _functions = functions;

  final FirebaseFunctions? _functions;

  FirebaseFunctions get _resolvedFunctions =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  Future<OfferWallCampaignPayload?> evaluateLaunch({
    required String sessionId,
  }) async {
    try {
      final data =
          await FirebaseResilienceService.retryTransient<Map<String, dynamic>>(
            operationName: 'offerWall.evaluateLaunch',
            operation: () async {
              final callable = _resolvedFunctions.httpsCallable(
                'evaluateOfferWallLaunch',
              );
              final result = await callable.call<dynamic>({
                'sessionId': sessionId,
              });
              final raw = result.data;
              if (raw is! Map) return const <String, dynamic>{'ok': false};
              return Map<String, dynamic>.from(raw);
            },
          );
      debugPrint(
        '[OfferWallDiag] flutter-evaluate-response rawHasCampaign=${data['campaign'] is Map}',
      );
      if (data['ok'] != true) return null;
      final campaignRaw = data['campaign'];
      if (campaignRaw is! Map) return null;
      try {
        final payload = OfferWallCampaignPayload.fromMap(
          Map<String, dynamic>.from(campaignRaw),
        );
        debugPrint(
          '[OfferWallDiag] flutter-payload-parsed campaignId=${payload.campaignId} creativeStoragePathPresent=${payload.creativeStoragePath.isNotEmpty} creativeUrlPresent=${payload.creativeUrl.isNotEmpty}',
        );
        return payload.isValid ? payload : null;
      } catch (error) {
        debugPrint(
          '[OfferWallDiag] flutter-payload-parse-failed errorType=${error.runtimeType}',
        );
        return null;
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> acknowledgeDisplayed({
    required OfferWallCampaignPayload payload,
  }) async {
    debugPrint(
      '[OfferWallDiag] acknowledge-start campaignId=${payload.campaignId} sessionId=${payload.sessionId}',
    );
    try {
      await FirebaseResilienceService.retryTransient<void>(
        operationName: 'offerWall.acknowledgeDisplayed',
        operation: () async {
          final callable = _resolvedFunctions.httpsCallable(
            'acknowledgeOfferWallDisplay',
          );
          await callable.call<dynamic>({
            'campaignId': payload.campaignId,
            'sessionId': payload.sessionId,
            'displayToken': payload.displayToken,
          });
        },
      );
      debugPrint(
        '[OfferWallDiag] acknowledge-success campaignId=${payload.campaignId}',
      );
    } catch (_) {
      debugPrint(
        '[OfferWallDiag] acknowledge-failed campaignId=${payload.campaignId} code=client-call-failed',
      );
      // Offer Wall is a non-blocking promotional feature.
    }
  }
}
