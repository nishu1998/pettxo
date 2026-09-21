import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettexo/features/bookings/domain/models/provider_earning_record.dart';

void main() {
  test('server reconstruction fixture is accepted by the strict Flutter parser', () {
    final data = jsonDecode(File('functions/test/fixtures/reconciled_provider_earning.json').readAsStringSync()) as Map<String, dynamic>;
    final record = ProviderEarningRecord.fromMap('b', data);
    expect(record.finalEntitlementPaise, 85000);
    expect(record.isProvisional, false);
    expect(record.providerId, 'provider');
    expect(record.createdAt, DateTime.utc(2026, 7, 24, 12));
  });
}
