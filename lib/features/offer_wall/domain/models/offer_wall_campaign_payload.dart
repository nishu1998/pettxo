class OfferWallCampaignPayload {
  const OfferWallCampaignPayload({
    required this.campaignId,
    required this.name,
    required this.creativeStoragePath,
    required this.displayToken,
    required this.sessionId,
    this.creativeUrl = '',
  });

  final String campaignId;
  final String name;
  final String creativeStoragePath;
  final String displayToken;
  final String sessionId;
  final String creativeUrl;

  factory OfferWallCampaignPayload.fromMap(Map<String, dynamic> data) {
    return OfferWallCampaignPayload(
      campaignId: '${data['campaignId'] ?? ''}'.trim(),
      name: '${data['name'] ?? ''}'.trim(),
      creativeUrl: '${data['creativeUrl'] ?? ''}'.trim(),
      creativeStoragePath: '${data['creativeStoragePath'] ?? ''}'.trim(),
      displayToken: '${data['displayToken'] ?? ''}'.trim(),
      sessionId: '${data['sessionId'] ?? ''}'.trim(),
    );
  }

  bool get isValid =>
      campaignId.isNotEmpty &&
      creativeStoragePath.isNotEmpty &&
      displayToken.isNotEmpty &&
      sessionId.isNotEmpty;
}
