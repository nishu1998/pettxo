import 'package:cloud_functions/cloud_functions.dart';

class MarketingEmailPreferenceService {
  MarketingEmailPreferenceService({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFunctions _functions;

  Future<bool> loadEnabled() async {
    final result = await _functions
        .httpsCallable('getMarketingEmailPreferenceV3')
        .call<Map<String, dynamic>>();
    return parseMarketingEmailPreference(result.data);
  }

  Future<bool> updateEnabled(bool enabled) async {
    final result = await _functions
        .httpsCallable('updateMarketingEmailPreferenceV3')
        .call<Map<String, dynamic>>({'enabled': enabled});
    return parseMarketingEmailPreference(result.data);
  }
}

bool parseMarketingEmailPreference(Map<String, dynamic> data) {
  return data['marketingEmailEnabled'] == true;
}
