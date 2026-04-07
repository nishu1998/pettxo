import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'core/services/analytics_service.dart';
import 'features/auth/presentation/screens/signin_screen.dart';
import 'features/auth/presentation/screens/signup_screen.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/splash/presentation/screens/splash_screen.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart'; // ✅ Use your theme

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const PettexoApp());
}

class PettexoApp extends StatelessWidget {
  const PettexoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pettexo',
      debugShowCheckedModeBanner: false,

      // ✅ Apply global theme (Poppins + colors)
      theme: AppTheme.lightTheme,
      navigatorObservers: [AnalyticsService.instance.observer],

      home: const CinematicSplash(),
      routes: {
        "/signup": (context) => const SignupScreen(),
        "/signin": (context) => const SigninScreen(),
        "/home": (context) => const HomeScreen(),
      },
    );
  }
}
