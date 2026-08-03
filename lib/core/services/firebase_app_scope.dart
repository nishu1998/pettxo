import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseAppScope {
  const FirebaseAppScope._();

  static FirebaseApp get app => Firebase.app();

  static FirebaseAuth auth() => FirebaseAuth.instanceFor(app: app);

  static FirebaseFunctions functions({String region = 'asia-south1'}) =>
      FirebaseFunctions.instanceFor(app: app, region: region);

  static void debugLogPair({
    required String context,
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  }) {
    if (!kDebugMode) return;
    final resolvedAuth = auth ?? FirebaseAppScope.auth();
    final resolvedFunctions = functions ?? FirebaseAppScope.functions();
    final authApp = resolvedAuth.app;
    final functionsApp = resolvedFunctions.app;
    debugPrint(
      'Firebase app debug -> context=$context authAppName=${authApp.name} authProjectId=${authApp.options.projectId} authAppId=${authApp.options.appId} functionsAppName=${functionsApp.name} functionsProjectId=${functionsApp.options.projectId} functionsAppId=${functionsApp.options.appId}',
    );
  }
}
