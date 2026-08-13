import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/offer_wall/domain/models/offer_wall_campaign_payload.dart';
import 'package:pettexo/features/offer_wall/presentation/widgets/offer_wall_dialog.dart';

void main() {
  testWidgets(
    'OfferWallDialog hides campaign metadata and closes from the branded button',
    (tester) async {
      var shownCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (_) => OfferWallDialog(
                        payload: const OfferWallCampaignPayload(
                          campaignId: 'campaign_1',
                          name: 'Independence Day',
                          creativeUrl: 'https://example.com/creative.webp',
                          creativeStoragePath:
                              'offerWalls/campaign_1/creative.webp',
                          displayToken: 'token_1',
                          sessionId: 'session_1',
                        ),
                        resolvedCreativeUrl: 'https://example.com/runtime.webp',
                        imageProvider: const AssetImage('assets/logo1024.png'),
                        onShown: () async {
                          shownCount += 1;
                        },
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(OfferWallDialog), findsOneWidget);
      expect(shownCount, 1);
      expect(find.text('Independence Day'), findsNothing);
      expect(find.text('campaign_1'), findsNothing);
      expect(find.bySemanticsLabel('Close Offer Wall'), findsOneWidget);

      final closeButtonSize = tester.getSize(
        find.bySemanticsLabel('Close Offer Wall'),
      );
      expect(closeButtonSize.width, greaterThanOrEqualTo(44));
      expect(closeButtonSize.height, greaterThanOrEqualTo(44));
      expect(find.byType(Image), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(OfferWallDialog), findsNothing);
    },
  );
}
