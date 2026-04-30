import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/provider_earning_record.dart';

class ProviderEarningsScreen extends StatelessWidget {
  ProviderEarningsScreen({super.key});

  final BookingRepository _bookingRepository = BookingRepository();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        title: const Text('Provider Earnings'),
      ),
      body: StreamBuilder<List<ProviderEarningRecord>>(
        stream: _bookingRepository.watchProviderEarnings(uid),
        builder: (context, snapshot) {
          final earnings = snapshot.data ?? const <ProviderEarningRecord>[];
          if (snapshot.connectionState == ConnectionState.waiting &&
              earnings.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (earnings.isEmpty) {
            return const Center(
              child: Text(
                'No earnings yet.',
                style: TextStyle(
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }

          final pending = _sumByStatus(earnings, const {'pending', 'hold'});
          final eligible = _sumByStatus(earnings, const {'payoutEligible'});
          final paid = _sumByStatus(earnings, const {'paid'});
          final disputed = _sumByStatus(earnings, const {'disputed'});
          final total =
              earnings.fold<int>(0, (sum, item) => sum + item.amountPaise);

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatCard(label: 'Total', value: _moneyFromPaise(total)),
                  _StatCard(
                    label: 'Pending',
                    value: _moneyFromPaise(pending),
                  ),
                  _StatCard(
                    label: 'Eligible',
                    value: _moneyFromPaise(eligible),
                  ),
                  _StatCard(label: 'Paid', value: _moneyFromPaise(paid)),
                  _StatCard(
                    label: 'On Hold',
                    value: _moneyFromPaise(disputed),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ...earnings.map(
                (earning) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking ${earning.bookingId}',
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Amount: ${_moneyFromPaise(earning.amountPaise)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Status: ${earning.status}',
                        style: const TextStyle(color: AppColors.textGrey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Source: ${earning.source}',
                        style: const TextStyle(color: AppColors.textGrey),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static int _sumByStatus(
    List<ProviderEarningRecord> earnings,
    Set<String> statuses,
  ) {
    return earnings
        .where((item) => statuses.contains(item.status))
        .fold<int>(0, (sum, item) => sum + item.amountPaise);
  }

  static String _moneyFromPaise(int paise) {
    final rupees = paise / 100;
    return paise % 100 == 0
        ? '₹${rupees.toStringAsFixed(0)}'
        : '₹${rupees.toStringAsFixed(2)}';
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textGrey),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
