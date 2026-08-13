import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/app_loader.dart';
import '../../../../core/services/firebase_resilience_service.dart';
import '../../../../core/services/network_status_service.dart';
import '../../domain/models/offer_wall_campaign_payload.dart';
import '../../presentation/widgets/offer_wall_dialog.dart';
import 'offer_wall_service.dart';

typedef OfferWallDialogPresenter =
    Future<void> Function(
      BuildContext context,
      OfferWallCampaignPayload payload,
      String resolvedCreativeUrl,
      OfferWallShownCallback onShown,
    );

typedef OfferWallImagePreloader =
    Future<void> Function(ImageProvider<Object> imageProvider);

typedef OfferWallStorageUrlResolver =
    Future<String> Function(String creativeStoragePath);

class OfferWallCoordinator {
  OfferWallCoordinator({
    FirebaseAuth? auth,
    OfferWallService? service,
    OfferWallDialogPresenter? dialogPresenter,
    OfferWallImagePreloader? imagePreloader,
    OfferWallStorageUrlResolver? storageUrlResolver,
    String Function()? currentUidProvider,
  }) : _service = service ?? OfferWallService(),
       _dialogPresenter = dialogPresenter ?? _defaultPresenter,
       _storageUrlResolver =
           storageUrlResolver ??
           ((creativeStoragePath) {
             return FirebaseStorage.instance
                 .ref(creativeStoragePath)
                 .getDownloadURL();
           }),
       _currentUidProvider =
           currentUidProvider ??
           (() =>
               (auth ?? FirebaseAuth.instance).currentUser?.uid.trim() ?? ''),
       _imagePreloader =
           imagePreloader ??
           ((imageProvider) async {
             final context = AppLoader.navigatorKey.currentContext;
             if (context == null || !context.mounted) {
               throw StateError('Offer Wall context is unavailable.');
             }
             await precacheImage(imageProvider, context);
           });

  OfferWallCoordinator._singleton() : this();

  static final OfferWallCoordinator instance =
      OfferWallCoordinator._singleton();

  final OfferWallService _service;
  final OfferWallDialogPresenter _dialogPresenter;
  final OfferWallImagePreloader _imagePreloader;
  final OfferWallStorageUrlResolver _storageUrlResolver;
  final String Function() _currentUidProvider;

  final Set<String> _evaluatedUserIdsThisProcess = <String>{};
  final String _sessionId = _buildSessionId();
  bool _evaluationInFlight = false;

  Future<void> handleAuthenticatedShellReady() async {
    final uid = _currentUidProvider();
    debugPrint(
      '[OfferWallDiag] process-session sessionId=$_sessionId uid=$uid',
    );
    debugPrint(
      '[OfferWallDiag] coordinator-start uid=$uid sessionId=$_sessionId',
    );
    if (uid.isEmpty) return;
    if (_evaluationInFlight) {
      debugPrint(
        '[OfferWallDiag] coordinator-skip reason=evaluation-in-flight',
      );
      return;
    }
    if (_evaluatedUserIdsThisProcess.contains(uid)) {
      debugPrint(
        '[OfferWallDiag] coordinator-skip reason=already-evaluated-this-process',
      );
      return;
    }
    _evaluatedUserIdsThisProcess.add(uid);

    if (NetworkStatusService.instance.isOffline) {
      debugPrint('[OfferWallDiag] coordinator-skip reason=offline');
      return;
    }

    _evaluationInFlight = true;
    try {
      final payload = await _service.evaluateLaunch(sessionId: _sessionId);
      if (payload == null) {
        debugPrint(
          '[OfferWallDiag] coordinator-skip reason=no-campaign-returned',
        );
        return;
      }
      debugPrint(
        '[OfferWallDiag] coordinator-campaign campaignId=${payload.campaignId}',
      );

      if (payload.creativeStoragePath.isEmpty) {
        debugPrint(
          '[OfferWallDiag] coordinator-skip reason=no-creative-storage-path',
        );
        return;
      }
      debugPrint(
        '[OfferWallDiag] storage-resolve-start campaignId=${payload.campaignId} path=${payload.creativeStoragePath}',
      );
      late final String resolvedCreativeUrl;
      try {
        resolvedCreativeUrl = await _storageUrlResolver(
          payload.creativeStoragePath,
        );
        debugPrint(
          '[OfferWallDiag] storage-resolve-success campaignId=${payload.campaignId}',
        );
      } catch (error) {
        final code = error is FirebaseException
            ? error.code
            : error.runtimeType;
        debugPrint(
          '[OfferWallDiag] storage-resolve-failed campaignId=${payload.campaignId} code=$code',
        );
        return;
      }

      await _imagePreloader(NetworkImage(resolvedCreativeUrl));
      final context = AppLoader.navigatorKey.currentContext;
      if (context == null || !context.mounted) {
        debugPrint(
          '[OfferWallDiag] dialog-not-shown reason=context-unavailable',
        );
        return;
      }

      var acknowledgementStarted = false;
      debugPrint(
        '[OfferWallDiag] dialog-show-start campaignId=${payload.campaignId}',
      );
      await _dialogPresenter(context, payload, resolvedCreativeUrl, () async {
        if (acknowledgementStarted) return;
        acknowledgementStarted = true;
        await _service.acknowledgeDisplayed(payload: payload);
      });
    } catch (error) {
      FirebaseResilienceService.logImageFailure(
        operationName: 'offerWall.display',
        error: error,
      );
    } finally {
      _evaluationInFlight = false;
    }
  }

  static Future<void> _defaultPresenter(
    BuildContext context,
    OfferWallCampaignPayload payload,
    String resolvedCreativeUrl,
    OfferWallShownCallback onShown,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => OfferWallDialog(
        payload: payload,
        resolvedCreativeUrl: resolvedCreativeUrl,
        onShown: onShown,
      ),
    );
  }

  static String _buildSessionId() {
    final random = Random();
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final salt = List.generate(
      4,
      (_) => random.nextInt(1 << 16).toRadixString(16).padLeft(4, '0'),
    ).join();
    return 'offerwall_$timestamp$salt';
  }
}
