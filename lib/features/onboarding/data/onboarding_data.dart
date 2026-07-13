import '../models/onboarding_model.dart';

class OnboardingLocalData {
  static List<OnboardingModel> getData() {
    return [
      OnboardingModel(
        tagLine: "Premium pet experience",
        title: "Connect & Explore Pets",
        subtitle: "Join a community of pet lovers and share moments.",
        backgroundImage: "assets/onboarding/community_background.png",
      ),
      OnboardingModel(
        tagLine: "Trusted care, easier",
        title: "Book Trusted Services",
        subtitle: "Find vets, groomers and trainers easily.",
        backgroundImage: "assets/onboarding/services_background.png",
      ),
      OnboardingModel(
        tagLine: "Discover what’s nearby",
        title: "Everything Nearby",
        subtitle: "Discover pet-friendly places around you.",
        backgroundImage: "assets/onboarding/trust_background.png",
      ),
    ];
  }
}
