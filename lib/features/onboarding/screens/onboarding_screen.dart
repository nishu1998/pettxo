import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/analytics_service.dart';
import '../data/services/onboarding_state_service.dart';
import '../models/onboarding_model.dart';
import '../widgets/onboarding_page.dart';
import '../widgets/onboarding_button.dart';
import '../widgets/onboarding_progress.dart';

import '../data/onboarding_repository.dart';
import '../../../core/services/remote_config_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController controller = PageController();
  final AnalyticsService analytics = AnalyticsService.instance;
  final OnboardingStateService onboardingState = OnboardingStateService();
  int currentIndex = 0;

  late List<OnboardingModel> onboardingList;

  final remote = RemoteConfigService(); // ✅ Remote config
  late OnboardingRepository repository; // ✅ Repository

  @override
  void initState() {
    super.initState();

    repository = OnboardingRepository(remote);

    // 🔥 Now using repository instead of local data
    onboardingList = repository.getOnboardingData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      analytics.logScreenView(
        screenName: 'onboarding',
        screenClass: 'OnboardingScreen',
      );
      _trackStepView(0);
    });
  }

  Future<void> nextPage() async {
    if (currentIndex < onboardingList.length - 1) {
      analytics.logOnboardingAction(
        action: 'next_tapped',
        stepIndex: currentIndex,
        totalSteps: onboardingList.length,
      );
      controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      analytics.logOnboardingAction(
        action: 'completed',
        stepIndex: currentIndex,
        totalSteps: onboardingList.length,
      );
      await onboardingState.markOnboardingSeen(remote.onboardingDisplayVersion);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, "/signup");
    }
  }

  Future<void> skip() async {
    analytics.logOnboardingAction(
      action: 'skipped',
      stepIndex: currentIndex,
      totalSteps: onboardingList.length,
    );
    await onboardingState.markOnboardingSeen(remote.onboardingDisplayVersion);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, "/signup");
  }

  void _trackStepView(int index) {
    analytics.logOnboardingStepViewed(
      stepIndex: index,
      totalSteps: onboardingList.length,
      title: onboardingList[index].title,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
              child: Row(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 26,
                        height: 26,
                        child: SvgPicture.asset(
                          'assets/brand/pettxo_logo.svg',
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Pettxo',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: TextButton(
                      onPressed: skip,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("Skip"),
                          SizedBox(width: 6),
                          Icon(Icons.arrow_forward_rounded, size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            OnboardingProgress(index: currentIndex),
            Expanded(
              child: PageView.builder(
                controller: controller,
                itemCount: onboardingList.length,
                onPageChanged: (index) {
                  setState(() => currentIndex = index);
                  _trackStepView(index);
                },
                itemBuilder: (_, index) {
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween(
                            begin: 0.98,
                            end: 1.0,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: OnboardingPage(
                      key: ValueKey(index),
                      data: onboardingList[index],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
