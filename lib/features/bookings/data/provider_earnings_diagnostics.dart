import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Error messages/details from services can contain private data. Emit only a
/// code and an allowlisted explanation, never the raw exception or document.
Map<String, Object?> providerEarningsErrorDiagnostic(Object error) {
  final code = error is FirebaseException ? error.code : null;
  final reconciliation =
      error is FirebaseFunctionsException &&
      error.details is Map &&
      (error.details as Map)['code'] == 'EARNINGS_RECONCILIATION_REQUIRED';
  return {
    'errorType': error.runtimeType.toString(),
    'firebaseCode': code,
    'message': reconciliation
        ? 'Earnings history requires reconciliation'
        : error is FormatException
        ? 'Invalid earnings data or account identity'
        : switch (code) {
            'permission-denied' => 'Request denied',
            'unauthenticated' => 'Authentication required',
            'failed-precondition' =>
              'Request precondition failed; inspect server diagnostics',
            'unavailable' => 'Service unavailable',
            _ => 'Earnings request failed',
          },
    if (reconciliation) 'reasonCode': 'EARNINGS_RECONCILIATION_REQUIRED',
  };
}

void logProviderEarningsDiagnostic(
  String section,
  Map<String, Object?> fields,
) {
  if (kDebugMode) {
    debugPrint('[ProviderEarnings$section] ${jsonEncode(fields)}');
  }
}
