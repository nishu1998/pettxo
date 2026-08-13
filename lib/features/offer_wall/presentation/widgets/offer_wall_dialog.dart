import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/models/offer_wall_campaign_payload.dart';

typedef OfferWallShownCallback = Future<void> Function();

class OfferWallDialog extends StatefulWidget {
  const OfferWallDialog({
    super.key,
    required this.payload,
    required this.resolvedCreativeUrl,
    required this.onShown,
    this.imageProvider,
  });

  final OfferWallCampaignPayload payload;
  final String resolvedCreativeUrl;
  final OfferWallShownCallback onShown;
  final ImageProvider<Object>? imageProvider;

  @override
  State<OfferWallDialog> createState() => _OfferWallDialogState();
}

class _OfferWallDialogState extends State<OfferWallDialog> {
  bool _reportedShown = false;
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final imageProvider =
          widget.imageProvider ?? NetworkImage(widget.resolvedCreativeUrl);
      debugPrint(
        '[OfferWallDiag] image-load-start campaignId=${widget.payload.campaignId}',
      );
      _imageStream = imageProvider.resolve(
        createLocalImageConfiguration(context),
      );
      _imageStreamListener = ImageStreamListener(
        (imageInfo, synchronousCall) {
          debugPrint(
            '[OfferWallDiag] image-load-success campaignId=${widget.payload.campaignId}',
          );
        },
        onError: (Object error, StackTrace? stackTrace) {
          debugPrint(
            '[OfferWallDiag] image-load-failed campaignId=${widget.payload.campaignId}',
          );
        },
      );
      _imageStream!.addListener(_imageStreamListener!);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_reportedShown) return;
      _reportedShown = true;
      debugPrint(
        '[OfferWallDiag] dialog-shown campaignId=${widget.payload.campaignId}',
      );
      widget.onShown();
    });
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageStreamListener != null) {
      _imageStream!.removeListener(_imageStreamListener!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardWidth = (screenWidth * 0.9).clamp(0.0, 420.0);
    const closeButtonSize = 44.0;
    const closeButtonRadius = 13.0;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: SizedBox(
        width: cardWidth,
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image(
                  image:
                      widget.imageProvider ??
                      NetworkImage(widget.resolvedCreativeUrl),
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 15,
                  right: 15,
                  child: Semantics(
                    button: true,
                    label: 'Close Offer Wall',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(closeButtonRadius),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.24),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(
                            closeButtonRadius,
                          ),
                          splashColor: AppColors.primary.withValues(alpha: 0.1),
                          highlightColor: AppColors.primary.withValues(
                            alpha: 0.05,
                          ),
                          onTap: () => Navigator.of(context).pop(),
                          child: const SizedBox(
                            width: closeButtonSize,
                            height: closeButtonSize,
                            child: Icon(
                              Icons.close_rounded,
                              color: AppColors.primary,
                              size: 23,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
