import '../models/onboarding_model.dart';
import 'onboarding_data.dart';
import '../../../core/services/remote_config_service.dart';

class OnboardingRepository {
  final RemoteConfigService remote;

  OnboardingRepository(this.remote);

  List<OnboardingModel> getOnboardingData() {
    final local = OnboardingLocalData.getData();

    return [
      OnboardingModel(
        title: remote.getString("title_1", local[0].title),
        subtitle: remote.getString("subtitle_1", local[0].subtitle),
        lottie: local[0].lottie,
      ),
      OnboardingModel(
        title: remote.getString("title_2", local[1].title),
        subtitle: remote.getString("subtitle_2", local[1].subtitle),
        lottie: local[1].lottie,
      ),
      OnboardingModel(
        title: remote.getString("title_3", local[2].title),
        subtitle: remote.getString("subtitle_3", local[2].subtitle),
        lottie: local[2].lottie,
      ),
    ];
  }
}