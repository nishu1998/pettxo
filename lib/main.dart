import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'core/services/analytics_service.dart';
import 'core/services/app_loader.dart';
import 'core/services/firebase_app_scope.dart';
import 'core/services/network_status_service.dart';
import 'core/services/policy_link_service.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/social_post_deep_link_service.dart';
import 'core/widgets/network_status_banner.dart';
import 'features/auth/presentation/screens/profile_type_screen.dart';
import 'features/auth/presentation/screens/auth_gateway_screen.dart';
import 'features/bookings/presentation/screens/bookings_screen.dart';
import 'features/bookings/presentation/screens/provider_earnings_screen.dart';
import 'features/auth/presentation/screens/signin_screen.dart';
import 'features/auth/presentation/screens/signin_with_phone_screen.dart';
import 'features/auth/presentation/screens/signup_screen.dart';
import 'features/auth/presentation/screens/signup_with_phone_screen.dart';
import 'features/auth/presentation/screens/email_verification_screen.dart';
import 'features/auth/presentation/screens/link_phone_screen.dart';
import 'features/explore/presentation/screens/explore_screen.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/messages/presentation/screens/messages_screen.dart';
import 'features/notifications/presentation/screens/notifications_screen.dart';
import 'features/offers/presentation/screens/my_offers_screen.dart';
import 'features/profile/presentation/screens/add_service_screen.dart';
import 'features/profile/presentation/screens/add_edit_pet_screen.dart';
import 'features/profile/presentation/screens/pet_detail_screen.dart';
import 'features/profile/presentation/screens/profile_screen.dart';
import 'features/restrictions/data/services/user_restriction_service.dart';
import 'features/services/presentation/screens/services_screen.dart';
import 'features/settings/presentation/screens/edit_profile_screen.dart';
import 'features/settings/presentation/screens/legal_policies_screen.dart';
import 'features/settings/presentation/screens/settings_screen.dart';
import 'features/social/presentation/screens/create_post_screen.dart';
import 'features/social/presentation/widgets/post_publish_status_host.dart';
import 'features/splash/presentation/screens/splash_screen.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart'; // ✅ Use your theme

void _debugStartupLog(String message) {
  if (!kDebugMode) return;
  debugPrint(message);
}

void _installFirebaseStartupDiagnostics() {
  if (!kDebugMode) return;

  FirebaseAuth.instance.authStateChanges().listen((user) {
    _debugStartupLog(
      'Firebase startup diagnostics -> timestamp=${DateTime.now().toIso8601String()} event=authStateChanges currentUserPresent=${user?.uid.trim().isNotEmpty == true} currentUserId=${user?.uid ?? ''}',
    );
  });

  FirebaseAuth.instance.idTokenChanges().listen((user) {
    _debugStartupLog(
      'Firebase startup diagnostics -> timestamp=${DateTime.now().toIso8601String()} event=idTokenChanges currentUserPresent=${user?.uid.trim().isNotEmpty == true} currentUserId=${user?.uid ?? ''}',
    );
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final app = await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  _debugStartupLog(
    'App startup debug -> timestamp=${DateTime.now().toIso8601String()} firebase initialized projectId=${app.options.projectId}, currentUserId=${FirebaseAuth.instance.currentUser?.uid ?? ''}',
  );
  FirebaseAppScope.debugLogPair(context: 'main.startup');
  _installFirebaseStartupDiagnostics();
  FirebaseMessaging.onBackgroundMessage(
    pettxoFirebaseMessagingBackgroundHandler,
  );
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
  }

  runApp(const PettexoApp());

  await NetworkStatusService.instance.initialize();

  Future<void>(() async {
    try {
      await PolicyLinkService.initialize();
    } catch (error) {
      _debugStartupLog('App startup debug -> policy link init skipped: $error');
    }
  });
  Future<void>(() async {
    try {
      await PushNotificationService.instance.initialize();
    } catch (error) {
      _debugStartupLog('App startup debug -> push init skipped: $error');
    }
  });
  Future<void>(() async {
    try {
      await UserRestrictionService.instance.initialize();
    } catch (error) {
      _debugStartupLog('App startup debug -> restriction init skipped: $error');
    }
  });
  Future<void>(() async {
    try {
      await SocialPostDeepLinkService.instance.initialize();
    } catch (error) {
      _debugStartupLog('App startup debug -> deep link init skipped: $error');
    }
  });
}

class PettexoApp extends StatelessWidget {
  const PettexoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pettxo',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppLoader.navigatorKey,
      builder: (context, child) {
        return NetworkStatusBannerHost(
          child: Stack(
            children: [
              SafeArea(
                top: false,
                left: false,
                right: false,
                bottom: true,
                maintainBottomViewPadding: true,
                child: child ?? const SizedBox.shrink(),
              ),
              const PostPublishStatusHost(),
            ],
          ),
        );
      },

      // ✅ Apply global theme (Poppins + colors)
      theme: AppTheme.lightTheme,
      navigatorObservers: [AnalyticsService.instance.observer],

      home: const CinematicSplash(),
      routes: {
        "/signup": (context) => const SignupScreen(),
        "/signin": (context) => const SigninScreen(),
        "/signup/phone": (context) => const SignUpWithPhoneScreen(),
        "/signin/phone": (context) => const SignInWithPhoneScreen(),
        "/auth-gate": (context) => const AuthGatewayScreen(),
        "/verify-email": (context) => const EmailVerificationScreen(),
        "/link-phone": (context) => const LinkPhoneScreen(),
        "/profile-type": (context) => const ProfileTypeScreen(),
        "/home": (context) => const HomeScreen(),
        "/services": (context) => const ServicesScreen(),
        "/bookings": (context) => const BookingsScreen(),
        "/settings/provider-earnings": (context) => ProviderEarningsScreen(),
        "/settings": (context) => const SettingsScreen(),
        "/settings/offers": (context) => MyOffersScreen(),
        "/settings/profile": (context) => const EditProfileScreen(),
        "/settings/legal": (context) => const LegalPoliciesScreen(),
        LegalPoliciesCatalog.cancellationPolicy.routeName: (context) =>
            const LegalPolicyDetailScreen(
              document: LegalPoliciesCatalog.cancellationPolicy,
            ),
        LegalPoliciesCatalog.refundPolicy.routeName: (context) =>
            const LegalPolicyDetailScreen(
              document: LegalPoliciesCatalog.refundPolicy,
            ),
        LegalPoliciesCatalog.termsAndConditions.routeName: (context) =>
            const LegalPolicyDetailScreen(
              document: LegalPoliciesCatalog.termsAndConditions,
            ),
        LegalPoliciesCatalog.privacyPolicy.routeName: (context) =>
            const LegalPolicyDetailScreen(
              document: LegalPoliciesCatalog.privacyPolicy,
            ),
        LegalPoliciesCatalog.providerPolicy.routeName: (context) =>
            const LegalPolicyDetailScreen(
              document: LegalPoliciesCatalog.providerPolicy,
            ),
        "/explore": (context) => const ExploreScreen(),
        "/create": (context) => const CreatePostScreen(),
        "/alerts": (context) => const NotificationsScreen(),
        "/messages": (context) => const MessagesScreen(),
        "/profile": (context) => const ProfileScreen(),
        "/profile/services/add": (context) => const AddServiceScreen(),
        "/profile/pets/add": (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final values = args is Map ? args : const <String, Object?>{};
          return AddEditPetScreen(ownerId: '${values['ownerId'] ?? ''}');
        },
        "/profile/pets/edit": (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final values = args is Map ? args : const <String, Object?>{};
          return AddEditPetScreen(
            ownerId: '${values['ownerId'] ?? ''}',
            petId: '${values['petId'] ?? ''}',
          );
        },
        "/profile/pets/detail": (context) {
          final args = ModalRoute.of(context)?.settings.arguments;
          final values = args is Map ? args : const <String, Object?>{};
          return PetDetailScreen(
            ownerUserId: '${values['ownerId'] ?? ''}',
            petId: '${values['petId'] ?? ''}',
          );
        },
      },
    );
  }
}
