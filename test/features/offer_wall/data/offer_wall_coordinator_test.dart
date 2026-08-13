import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/core/services/app_loader.dart';
import 'package:pettexo/features/offer_wall/data/services/offer_wall_coordinator.dart';
import 'package:pettexo/features/offer_wall/data/services/offer_wall_service.dart';
import 'package:pettexo/features/offer_wall/domain/models/offer_wall_campaign_payload.dart';

class _FakeOfferWallService extends OfferWallService {
  _FakeOfferWallService({this.payload});

  final OfferWallCampaignPayload? payload;
  int evaluateCount = 0;
  int acknowledgeCount = 0;

  @override
  Future<OfferWallCampaignPayload?> evaluateLaunch({
    required String sessionId,
  }) async {
    evaluateCount += 1;
    return payload;
  }

  @override
  Future<void> acknowledgeDisplayed({
    required OfferWallCampaignPayload payload,
  }) async {
    acknowledgeCount += 1;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppLoader.navigatorKey,
        home: const Scaffold(body: SizedBox.shrink()),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'coordinator uses creativeStoragePath resolution and does not require creativeUrl',
    (tester) async {
      final service = _FakeOfferWallService(
        payload: const OfferWallCampaignPayload(
          campaignId: 'campaign_1',
          name: 'Welcome',
          creativeStoragePath: 'offerWalls/campaign_1/creative.png',
          displayToken: 'token_1',
          sessionId: 'session_1',
        ),
      );
      var resolvedUrl = '';
      var shownCount = 0;
      var preloadedCount = 0;

      final coordinator = OfferWallCoordinator(
        service: service,
        currentUidProvider: () => 'user_1',
        storageUrlResolver: (path) async {
          expect(path, 'offerWalls/campaign_1/creative.png');
          resolvedUrl = 'https://example.com/runtime.png';
          return resolvedUrl;
        },
        imagePreloader: (imageProvider) async {
          preloadedCount += 1;
          expect(imageProvider, isA<NetworkImage>());
          expect((imageProvider as NetworkImage).url, resolvedUrl);
        },
        dialogPresenter:
            (context, payload, resolvedCreativeUrl, onShown) async {
              shownCount += 1;
              expect(payload.creativeUrl, isEmpty);
              expect(resolvedCreativeUrl, resolvedUrl);
              await onShown();
            },
      );

      await pumpHost(tester);
      await coordinator.handleAuthenticatedShellReady();

      expect(service.evaluateCount, 1);
      expect(preloadedCount, 1);
      expect(shownCount, 1);
      expect(service.acknowledgeCount, 1);
    },
  );

  testWidgets(
    'coordinator skips dialog and acknowledgement when storage resolution fails',
    (tester) async {
      final service = _FakeOfferWallService(
        payload: const OfferWallCampaignPayload(
          campaignId: 'campaign_2',
          name: 'Welcome',
          creativeStoragePath: 'offerWalls/campaign_2/creative.png',
          displayToken: 'token_2',
          sessionId: 'session_2',
        ),
      );
      var shownCount = 0;
      var preloadedCount = 0;

      final coordinator = OfferWallCoordinator(
        service: service,
        currentUidProvider: () => 'user_1',
        storageUrlResolver: (path) async {
          throw Exception('storage failed');
        },
        imagePreloader: (imageProvider) async {
          preloadedCount += 1;
        },
        dialogPresenter:
            (context, payload, resolvedCreativeUrl, onShown) async {
              shownCount += 1;
            },
      );

      await pumpHost(tester);
      await coordinator.handleAuthenticatedShellReady();

      expect(service.evaluateCount, 1);
      expect(preloadedCount, 0);
      expect(shownCount, 0);
      expect(service.acknowledgeCount, 0);
    },
  );

  testWidgets('coordinator evaluates once per process for repeated triggers', (
    tester,
  ) async {
    final service = _FakeOfferWallService(
      payload: const OfferWallCampaignPayload(
        campaignId: 'campaign_3',
        name: 'Welcome',
        creativeStoragePath: 'offerWalls/campaign_3/creative.png',
        displayToken: 'token_3',
        sessionId: 'session_3',
      ),
    );

    final coordinator = OfferWallCoordinator(
      service: service,
      currentUidProvider: () => 'user_1',
      storageUrlResolver: (path) async => 'https://example.com/runtime.png',
      imagePreloader: (imageProvider) async {},
      dialogPresenter: (context, payload, resolvedCreativeUrl, onShown) async {
        await onShown();
      },
    );

    await pumpHost(tester);
    await coordinator.handleAuthenticatedShellReady();
    await coordinator.handleAuthenticatedShellReady();

    expect(service.evaluateCount, 1);
    expect(service.acknowledgeCount, 1);
  });
}
