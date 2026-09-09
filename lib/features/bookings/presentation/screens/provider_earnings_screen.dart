import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/widgets/pettxo_loading_animation.dart';
import '../../data/repositories/booking_repository.dart';
import '../../domain/models/provider_earning_record.dart';
import '../../domain/models/provider_earnings_summary.dart';
import '../utils/provider_earnings_presentation.dart';
import 'canonical_booking_detail_screen.dart';

class ProviderEarningsScreen extends StatefulWidget {
  const ProviderEarningsScreen({super.key, this.repository, this.auth});

  final BookingRepository? repository;
  final FirebaseAuth? auth;

  @override
  State<ProviderEarningsScreen> createState() => _ProviderEarningsScreenState();
}

class _ProviderEarningsScreenState extends State<ProviderEarningsScreen> {
  late final FirebaseAuth _auth = widget.auth ?? FirebaseAuth.instance;
  late final BookingRepository _repository =
      widget.repository ?? BookingRepository();
  late final Stream<String?> _users = _auth
      .authStateChanges()
      .map((user) => user?.uid)
      .distinct();

  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
    stream: _users,
    initialData: _auth.currentUser?.uid,
    builder: (context, snapshot) {
      final uid = snapshot.hasError ? null : snapshot.data;
      if (uid == null || uid.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('Provider Earnings')),
          body: const Center(child: Text('Sign in to view your earnings.')),
        );
      }
      // Changing accounts disposes both old data sources and their visible data.
      return _EarningsContent(
        key: ValueKey(uid),
        uid: uid,
        repository: _repository,
      );
    },
  );
}

class _EarningsContent extends StatefulWidget {
  const _EarningsContent({
    super.key,
    required this.uid,
    required this.repository,
  });
  final String uid;
  final BookingRepository repository;

  @override
  State<_EarningsContent> createState() => _EarningsContentState();
}

class _EarningsContentState extends State<_EarningsContent> {
  ProviderEarningsSummary? _summary;
  List<ProviderEarningRecord>? _history;
  bool _summaryError = false;
  bool _historyError = false;
  bool _summaryLoading = true;
  StreamSubscription<List<ProviderEarningRecord>>? _historySubscription;
  Future<void>? _refreshing;

  @override
  void initState() {
    super.initState();
    _listenToHistory();
    _refreshing = _loadSummary().whenComplete(() => _refreshing = null);
  }

  void _listenToHistory() {
    _historySubscription = widget.repository
        .watchProviderEarnings(widget.uid)
        .listen(
          (rows) {
            if (!mounted) return;
            if (rows.any((row) => row.providerId != widget.uid)) {
              setState(() {
                _historyError = true;
                _history = null;
              });
              return;
            }
            setState(() {
              _history = rows;
              _historyError = false;
            });
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _historyError = true;
                _history = null;
              });
            }
          },
        );
  }

  Future<void> _loadSummary() async {
    try {
      final result = await widget.repository.getProviderEarningsSummary();
      if (result.providerId != widget.uid) {
        throw const FormatException('Account changed');
      }
      if (mounted) {
        setState(() {
          _summary = result;
          _summaryError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _summary = null;
          _summaryError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _summaryLoading = false);
    }
  }

  Future<void> _refresh() =>
      _refreshing ??= _reload().whenComplete(() => _refreshing = null);

  Future<void> _reload() async {
    setState(() {
      _summaryLoading = true;
      _summaryError = false;
    });
    if (_historyError) {
      await _historySubscription?.cancel();
      if (!mounted) return;
      setState(() {
        _historyError = false;
        _history = null;
      });
      _listenToHistory();
    }
    await _loadSummary();
  }

  @override
  void dispose() {
    _historySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = _history?.where((row) => row.isVisible).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider Earnings'),
        actions: [
          IconButton(
            tooltip: 'Refresh earnings',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(18),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Earned', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 12),
                      if (_summaryLoading)
                        _loading(context, 'Loading lifetime earnings')
                      else if (_summaryError)
                        _retry(
                          'We couldn’t load your lifetime earnings.',
                          'Retry total',
                        )
                      else if (_summary != null) ...[
                        // Wrapping preserves the entire amount at large text scales.
                        Text(
                          formatEarningsPaise(_summary!.lifetimeEarnedPaise),
                          key: const Key('lifetime-total'),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Lifetime provider earnings',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          'Last refreshed ${formatEarningsDate(_summary!.asOf)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Earnings History', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              const Text('Recent records · Up to 120 bookings'),
              const SizedBox(height: 16),
              if (_historyError)
                _retry(
                  'We couldn’t load your earnings history.',
                  'Retry history',
                )
              else if (rows == null)
                if (_summaryLoading)
                  const Text('Loading earnings history…')
                else
                  _loading(context, 'Loading earnings history')
              else if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      Text(
                        _summary?.lifetimeEarnedPaise == 0 &&
                                !_summaryError &&
                                !_summaryLoading
                            ? 'No earnings yet'
                            : 'No recent earnings to show',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Your service earnings and booking outcomes will appear here.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                ...rows.map((row) => _record(context, row)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loading(BuildContext context, String message) => Center(
    child: Semantics(
      label: message,
      liveRegion: true,
      child: PettxoLoadingAnimation(
        size: 100,
        message: message,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    ),
  );

  Widget _retry(String message, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(message),
      TextButton(onPressed: _refresh, child: Text(label)),
    ],
  );

  Widget _record(BuildContext context, ProviderEarningRecord row) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  CanonicalBookingDetailScreen(bookingId: row.bookingId),
            ),
          );
          if (mounted) await _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Booking ${row.bookingId}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(earningsOutcomeLabel(row)),
              const SizedBox(height: 8),
              Text(
                row.isProvisional
                    ? 'Amount not final yet'
                    : formatEarningsPaise(row.finalEntitlementPaise!),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(earningsStatusLabel(row)),
              if (row.isProvisional)
                const Text('Not included in Total Earned yet.'),
              const SizedBox(height: 8),
              Text(
                row.displayDate == null
                    ? 'Date unavailable'
                    : '${row.dateLabel} ${formatEarningsDate(row.displayDate!)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              const Text('View booking'),
            ],
          ),
        ),
      ),
    );
  }
}
