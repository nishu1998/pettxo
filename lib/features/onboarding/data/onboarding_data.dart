import '../models/onboarding_model.dart';

class OnboardingLocalData {
  static List<OnboardingModel> getData() {
    return [
      OnboardingModel(
        title: "Connect & Explore Pets",
        subtitle: "Join a community of pet lovers and share moments.",
        lottie: "assets/lottie/social.json",
      ),
      OnboardingModel(
        title: "Book Trusted Services",
        subtitle: "Find vets, groomers and trainers easily.",
        lottie: "assets/lottie/services.json",
      ),
      OnboardingModel(
        title: "Everything Nearby",
        subtitle: "Discover pet-friendly places around you.",
        lottie: "assets/lottie/location.json",
      ),
    ];
  }
}