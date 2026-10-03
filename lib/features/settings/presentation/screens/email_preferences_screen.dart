import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../data/services/marketing_email_preference_service.dart';

class EmailPreferencesScreen extends StatefulWidget {
  const EmailPreferencesScreen({
    super.key,
    MarketingEmailPreferenceService? marketingEmailPreferenceService,
    Future<bool> Function()? loadPreferenceOverride,
    Future<bool> Function(bool enabled)? updatePreferenceOverride,
  }) : _marketingEmailPreferenceService = marketingEmailPreferenceService,
       _loadPreferenceOverride = loadPreferenceOverride,
       _updatePreferenceOverride = updatePreferenceOverride;

  final MarketingEmailPreferenceService? _marketingEmailPreferenceService;
  final Future<bool> Function()? _loadPreferenceOverride;
  final Future<bool> Function(bool enabled)? _updatePreferenceOverride;

  @override
  State<EmailPreferencesScreen> createState() => _EmailPreferencesScreenState();
}

class _EmailPreferencesScreenState extends State<EmailPreferencesScreen> {
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _marketingEmailEnabled = false;
  String? _loadError;

  MarketingEmailPreferenceService get _service =>
      widget._marketingEmailPreferenceService ??
      MarketingEmailPreferenceService();

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final enabled =
          await widget._loadPreferenceOverride?.call() ??
          await _service.loadEnabled();
      if (!mounted) return;
      setState(() {
        _marketingEmailEnabled = enabled;
        _loadError = null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'We could not load your email preference right now.';
        _isLoading = false;
      });
    }
  }

  Future<void> _updatePreference(bool enabled) async {
    if (_isUpdating) return;
    final previous = _marketingEmailEnabled;
    setState(() {
      _marketingEmailEnabled = enabled;
      _isUpdating = true;
    });
    try {
      final saved =
          await widget._updatePreferenceOverride?.call(enabled) ??
          await _service.updateEnabled(enabled);
      if (!mounted) return;
      setState(() => _marketingEmailEnabled = saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _marketingEmailEnabled = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not update your email preference.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBF6EF),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Email Preferences',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _loadError != null
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Text(
                            _loadError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textGrey),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() => _isLoading = true);
                              _loadPreference();
                            },
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    )
                  : SwitchListTile(
                      secondary: const Icon(
                        Icons.mark_email_read_outlined,
                        color: AppColors.primary,
                      ),
                      title: const Text(
                        'Offers & Pettxo updates',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: const Text(
                        'Optional offers and news. Essential account and service emails are unaffected.',
                        style: TextStyle(
                          color: AppColors.textGrey,
                          height: 1.4,
                        ),
                      ),
                      value: _marketingEmailEnabled,
                      onChanged: _isUpdating ? null : _updatePreference,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
