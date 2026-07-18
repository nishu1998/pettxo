import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../data/services/auth_service.dart';
import 'auth_gateway_screen.dart';

class AccountRecoveryScreen extends StatefulWidget {
  final String accountStatus;
  final DateTime? scheduledDeletionAt;

  const AccountRecoveryScreen({
    super.key,
    required this.accountStatus,
    this.scheduledDeletionAt,
  });

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;
  bool _isRestoring = false;
  DateTime? _scheduledDeletionAt;
  String _maskedEmail = '';
  String _maskedPhone = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('Sign in again to continue.');
      }

      final privateSnapshot = await FirebaseFirestore.instance
          .collection('userPrivate')
          .doc(user.uid)
          .get();
      final data = privateSnapshot.data() ?? const <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _scheduledDeletionAt = data['scheduledDeletionAt'] is Timestamp
            ? (data['scheduledDeletionAt'] as Timestamp).toDate()
            : widget.scheduledDeletionAt;
        _maskedEmail = _maskEmail((user.email ?? '').trim());
        _maskedPhone = _maskPhone((user.phoneNumber ?? '').trim());
        _isLoading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _scheduledDeletionAt = widget.scheduledDeletionAt;
        _maskedEmail = _maskEmail(
          (FirebaseAuth.instance.currentUser?.email ?? '').trim(),
        );
        _maskedPhone = _maskPhone(
          (FirebaseAuth.instance.currentUser?.phoneNumber ?? '').trim(),
        );
        _isLoading = false;
        _error = 'We could not load your recovery details right now.';
      });
    }
  }

  Future<void> _restoreAccount() async {
    if (_isRestoring) return;
    setState(() => _isRestoring = true);
    try {
      await _authService.restoreAccount();
      await _authService.reloadCurrentUser(syncTrustedIdentity: true);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              const AuthGatewayScreen(reloadUserBeforeResolve: true),
        ),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isRestoring = false);
      AppFeedback.show(
        context,
        message: error.toString().replaceFirst('Exception: ', ''),
        tone: AppFeedbackTone.error,
      );
    }
  }

  Future<void> _continueDeletion() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGatewayScreen()),
      (route) => false,
    );
  }

  String _maskEmail(String email) {
    if (!email.contains('@')) return '';
    final parts = email.split('@');
    final localPart = parts.first;
    if (localPart.isEmpty) return email;
    final prefix = localPart.substring(0, localPart.length >= 2 ? 2 : 1);
    return '$prefix••••@${parts.last}';
  }

  String _maskPhone(String phone) {
    if (phone.isEmpty || phone.length < 4) return phone;
    final countryPrefixLength = phone.length > 10 ? phone.length - 10 : 0;
    final prefix = countryPrefixLength > 0
        ? phone.substring(0, countryPrefixLength)
        : '';
    return '$prefix ••••••${phone.substring(phone.length - 4)}'.trim();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Unavailable';
    const months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  int _remainingDays(DateTime? date) {
    if (date == null) return 0;
    final now = DateTime.now();
    final difference = date.difference(now).inHours / 24;
    return difference <= 0 ? 0 : difference.ceil();
  }

  @override
  Widget build(BuildContext context) {
    final isDeletionInProgress =
        widget.accountStatus.trim() == 'deletionInProgress';
    final scheduledDeletionAt = _scheduledDeletionAt;
    final remainingDays = _remainingDays(scheduledDeletionAt);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 460),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 24,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradientDiagonal,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.restore_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          isDeletionInProgress
                              ? 'Your account deletion is already in progress'
                              : 'Your account is scheduled for deletion',
                          style: TextStyle(
                            color: AppColors.textDark,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          isDeletionInProgress
                              ? 'This account can no longer be restored. Sign out while Pettxo completes permanent deletion.'
                              : 'Access is paused immediately. Sign in during the 30-day recovery window to restore this Pettxo account and keep the same UID, username, bookings, chats, and profile.',
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        _RecoveryInfoRow(
                          label: 'Scheduled deletion',
                          value: _formatDate(scheduledDeletionAt),
                        ),
                        _RecoveryInfoRow(
                          label: 'Days remaining',
                          value: '$remainingDays',
                        ),
                        if (_maskedEmail.isNotEmpty)
                          _RecoveryInfoRow(
                            label: 'Linked email',
                            value: _maskedEmail,
                          ),
                        if (_maskedPhone.isNotEmpty)
                          _RecoveryInfoRow(
                            label: 'Linked phone',
                            value: _maskedPhone,
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: 18),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFB42318),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 26),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isDeletionInProgress || _isRestoring
                                ? null
                                : _restoreAccount,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: _isRestoring
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    isDeletionInProgress
                                        ? 'Restoration unavailable'
                                        : 'Restore Account',
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _continueDeletion,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textDark,
                              side: const BorderSide(color: Color(0xFFE7D9CF)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('Continue Deletion'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _continueDeletion,
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _RecoveryInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _RecoveryInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
