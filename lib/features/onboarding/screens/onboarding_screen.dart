import 'package:flutter/material.dart';

import '../models/onboarding_model.dart';
import '../widgets/onboarding_page.dart';
import '../widgets/onboarding_button.dart';
import '../widgets/onboarding_progress.dart';

import '../data/onboarding_repository.dart';
import '../../../core/services/remote_config_service.dart';

class OnboardingScreen extends StatefulWidget {
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController controller = PageController();
  int currentIndex = 0;

  late List<OnboardingModel> onboardingList;

  final remote = RemoteConfigService();          // ✅ Remote config
  late OnboardingRepository repository;          // ✅ Repository

  @override
  void initState() {
    super.initState();

    repository = OnboardingRepository(remote);

    // 🔥 Now using repository instead of local data
    onboardingList = repository.getOnboardingData();
  }

  void nextPage() {
    if (currentIndex < onboardingList.length - 1) {
      controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pushReplacementNamed(context, "/signup");
    }
  }

  void skip() {
    Navigator.pushReplacementNamed(context, "/signup");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [

            /// 🔥 Skip Button
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: skip,
                child: const Text("Skip"),
              ),
            ),

            /// 🔥 Progress Bar
            OnboardingProgress(index: currentIndex),

            /// 🔥 Pages
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: onboardingList.length,
                onPageChanged: (index) {
                  setState(() => currentIndex = index);
                },
                itemBuilder: (_, index) {
                  return OnboardingPage(data: onboardingList[index]);
                },
              ),
            ),

            /// 🔥 Button
            Padding(
              padding: const EdgeInsets.all(20),
              child: OnboardingButton(
                text: currentIndex == onboardingList.length - 1
                    ? "Get Started"
                    : "Next",
                onTap: nextPage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}