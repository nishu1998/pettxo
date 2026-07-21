import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/app_confirmation_dialog.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_glass_overlay.dart';
import '../../data/repositories/pet_repository.dart';
import '../../domain/models/pet_profile.dart';
import 'add_edit_pet_screen.dart';

class PetDetailScreen extends StatefulWidget {
  final String ownerUserId;
  final String petId;

  const PetDetailScreen({
    super.key,
    required this.ownerUserId,
    required this.petId,
  });

  @override
  State<PetDetailScreen> createState() => _PetDetailScreenState();
}

class _PetDetailScreenState extends State<PetDetailScreen> {
  final PetRepository _repository = PetRepository();
  bool _isDeleting = false;

  Future<void> _confirmDelete(PetProfile pet) async {
    if (_isDeleting) return;
    final confirmed = await AppConfirmationDialog.show(
      context: context,
      title: 'Delete pet?',
      message:
          'Remove ${pet.name} from your profile? This keeps existing records safe but hides the pet publicly.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await _repository.softDeletePet(ownerId: pet.ownerId, petId: pet.id);
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: '${pet.name} was removed from your profile.',
        tone: AppFeedbackTone.success,
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        message: 'Unable to delete pet right now.',
        tone: AppFeedbackTone.error,
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _openOwnerMenu(PetProfile pet) async {
    if (_isDeleting) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return AppGlassBottomSheetFrame(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PetActionRow(
                icon: Icons.edit_rounded,
                label: 'Edit pet',
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddEditPetScreen(
                        ownerId: pet.ownerId,
                        petId: pet.id,
                        initialPet: pet,
                      ),
                    ),
                  );
                },
              ),
              Divider(
                height: 1,
                color: AppColors.textGrey.withValues(alpha: 0.12),
              ),
              _PetActionRow(
                icon: Icons.delete_outline_rounded,
                label: 'Delete pet',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDelete(pet);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final isOwner = currentUid.isNotEmpty && currentUid == widget.ownerUserId;

    return StreamBuilder<PetProfile?>(
      stream: _repository.watchPet(
        ownerId: widget.ownerUserId,
        petId: widget.petId,
      ),
      builder: (context, snapshot) {
        final pet = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting &&
            pet == null) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (pet == null) {
          return const _MissingPetDetailsState();
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                _PetDetailsHeader(
                  title: pet.name,
                  isOwner: isOwner,
                  isDeleting: _isDeleting,
                  onMenuTap: () => _openOwnerMenu(pet),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                    children: [
                      _PetHeroCard(pet: pet),
                      const SizedBox(height: 16),
                      _PetInfoCard(
                        title: 'BASICS',
                        rows: [
                          if (pet.breed.isNotEmpty)
                            _InfoRowData(label: 'Breed', value: pet.breed),
                          if (pet.dateOfBirth != null)
                            _InfoRowData(
                              label: 'Age',
                              value: _formatPetAge(pet.dateOfBirth!),
                            ),
                          if (pet.dateOfBirth != null)
                            _InfoRowData(
                              label: 'Date of birth',
                              value: _formatDate(pet.dateOfBirth!),
                            ),
                          if (pet.weightKg != null)
                            _InfoRowData(
                              label: 'Weight',
                              value: '${_formatWeight(pet.weightKg!)} kg',
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _PetHealthCard(pet: pet),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PetDetailsHeader extends StatelessWidget {
  final String title;
  final bool isOwner;
  final bool isDeleting;
  final VoidCallback onMenuTap;

  const _PetDetailsHeader({
    required this.title,
    required this.isOwner,
    required this.isDeleting,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textDark,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (isOwner)
            SizedBox(
              width: 46,
              height: 46,
              child: IconButton(
                tooltip: 'Pet actions',
                onPressed: isDeleting ? null : onMenuTap,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: isDeleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.more_horiz_rounded),
              ),
            ),
        ],
      ),
    );
  }
}

class _PetHeroCard extends StatelessWidget {
  final PetProfile pet;

  const _PetHeroCard({required this.pet});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
            child: SizedBox(
              height: 300,
              width: double.infinity,
              child: pet.photoUrl.isEmpty
                  ? const _PetDetailsPlaceholder()
                  : Image.network(
                      pet.photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _PetDetailsPlaceholder(),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pet.name,
                  style: const TextStyle(
                    color: AppColors.textDark,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PetBadge(label: pet.animalType, isPrimary: true),
                    _PetBadge(label: pet.sex),
                  ],
                ),
                if (pet.bio.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    pet.bio,
                    style: const TextStyle(
                      color: AppColors.textDark,
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PetBadge extends StatelessWidget {
  final String label;
  final bool isPrimary;

  const _PetBadge({required this.label, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isPrimary
            ? AppColors.primary.withValues(alpha: 0.12)
            : AppColors.textGrey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isPrimary ? AppColors.primary : AppColors.textGrey,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _PetInfoCard extends StatelessWidget {
  final String title;
  final List<_InfoRowData> rows;

  const _PetInfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title),
          const SizedBox(height: 8),
          ...rows.map((row) => _PetInfoRow(label: row.label, value: row.value)),
        ],
      ),
    );
  }
}

class _PetHealthCard extends StatelessWidget {
  final PetProfile pet;

  const _PetHealthCard({required this.pet});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _PetInfoRow(
        label: 'Vaccinated',
        value: pet.isVaccinated
            ? pet.vaccinationDate == null
                  ? 'Yes'
                  : _formatDate(pet.vaccinationDate!)
            : 'No',
        valuePillTone: pet.isVaccinated ? _PillTone.success : _PillTone.neutral,
      ),
      _PetInfoRow(
        label: 'Dewormed',
        value: pet.isDewormed
            ? pet.dewormingDate == null
                  ? 'Yes'
                  : _formatDate(pet.dewormingDate!)
            : 'No',
        valuePillTone: pet.isDewormed ? _PillTone.success : _PillTone.neutral,
      ),
      if (pet.knownAllergies.isNotEmpty)
        _PetInfoRow(label: 'Known allergies', value: pet.knownAllergies),
      if (pet.regularVet.isNotEmpty)
        _PetInfoRow(label: 'Regular vet', value: pet.regularVet),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('HEALTH'),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }
}

class _PetInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final _PillTone? valuePillTone;

  const _PetInfoRow({
    required this.label,
    required this.value,
    this.valuePillTone,
  });

  @override
  Widget build(BuildContext context) {
    final pillTone = valuePillTone;
    final valueWidget = pillTone == null
        ? Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: AppColors.textDark,
              fontWeight: FontWeight.w700,
            ),
          )
        : _StatusPill(value: value, tone: pillTone);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textGrey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(child: valueWidget),
        ],
      ),
    );
  }
}

class _InfoRowData {
  final String label;
  final String value;

  const _InfoRowData({required this.label, required this.value});
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.textGrey,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.8,
      ),
    );
  }
}

enum _PillTone { success, neutral }

class _StatusPill extends StatelessWidget {
  final String value;
  final _PillTone tone;

  const _StatusPill({required this.value, required this.tone});

  @override
  Widget build(BuildContext context) {
    final isSuccess = tone == _PillTone.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isSuccess
            ? const Color(0xFFE7F7EF)
            : AppColors.textGrey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: isSuccess ? const Color(0xFF15803D) : AppColors.textGrey,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _PetDetailsPlaceholder extends StatelessWidget {
  const _PetDetailsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradientDiagonal,
      ),
      child: const Icon(Icons.pets_rounded, color: Colors.white, size: 74),
    );
  }
}

class _PetActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  final VoidCallback onTap;

  const _PetActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.redAccent : AppColors.textDark;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingPetDetailsState extends StatelessWidget {
  const _MissingPetDetailsState();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.pets_rounded,
                  color: AppColors.primary,
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pet not found',
                  style: TextStyle(
                    color: AppColors.textDark,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This pet may have been removed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textGrey),
                ),
                const SizedBox(height: 18),
                SecondaryButton(
                  label: 'Go back',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _formatWeight(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _formatPetAge(DateTime birthDate) {
  final today = DateTime.now();
  var years = today.year - birthDate.year;
  var months = today.month - birthDate.month;
  if (today.day < birthDate.day) months -= 1;
  if (months < 0) {
    years -= 1;
    months += 12;
  }
  if (years <= 0) {
    return months <= 1 ? '$months mo' : '$months mo';
  }
  if (months == 0) return years == 1 ? '1 yr' : '$years yrs';
  return '${years == 1 ? '1 yr' : '$years yrs'} $months mo';
}
