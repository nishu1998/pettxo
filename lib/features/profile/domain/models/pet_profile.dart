import 'package:cloud_firestore/cloud_firestore.dart';

class PetProfile {
  final String id;
  final String ownerId;
  final String name;
  final String animalType;
  final String sex;
  final String breed;
  final DateTime? dateOfBirth;
  final double? weightKg;
  final String photoUrl;
  final String bio;
  final bool isVaccinated;
  final DateTime? vaccinationDate;
  final bool isDewormed;
  final DateTime? dewormingDate;
  final String knownAllergies;
  final String regularVet;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isDeleted;

  const PetProfile({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.animalType,
    required this.sex,
    this.breed = '',
    this.dateOfBirth,
    this.weightKg,
    this.photoUrl = '',
    this.bio = '',
    this.isVaccinated = false,
    this.vaccinationDate,
    this.isDewormed = false,
    this.dewormingDate,
    this.knownAllergies = '',
    this.regularVet = '',
    this.createdAt,
    this.updatedAt,
    this.isDeleted = false,
  });

  factory PetProfile.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return PetProfile.fromMap({...data, 'id': document.id});
  }

  factory PetProfile.fromMap(Map<String, dynamic> data) {
    final weightValue = data['weightKg'];
    return PetProfile(
      id: (data['id'] as String? ?? '').trim(),
      ownerId: (data['ownerId'] as String? ?? '').trim(),
      name: (data['name'] as String? ?? '').trim(),
      animalType: (data['animalType'] as String? ?? '').trim(),
      sex: (data['sex'] as String? ?? '').trim(),
      breed: (data['breed'] as String? ?? '').trim(),
      dateOfBirth: _readDate(data['dateOfBirth']),
      weightKg: weightValue is num ? weightValue.toDouble() : null,
      photoUrl: (data['photoUrl'] as String? ?? '').trim(),
      bio: (data['bio'] as String? ?? '').trim(),
      isVaccinated: data['isVaccinated'] as bool? ?? false,
      vaccinationDate: _readDate(data['vaccinationDate']),
      isDewormed: data['isDewormed'] as bool? ?? false,
      dewormingDate: _readDate(data['dewormingDate']),
      knownAllergies: (data['knownAllergies'] as String? ?? '').trim(),
      regularVet: (data['regularVet'] as String? ?? '').trim(),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
      isDeleted: data['isDeleted'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toSaveMap({
    required Object createdAt,
    required Object updatedAt,
  }) {
    return {
      'id': id,
      'ownerId': ownerId,
      'name': name.trim(),
      'animalType': animalType.trim(),
      'sex': sex.trim(),
      'breed': breed.trim(),
      'dateOfBirth': dateOfBirth == null
          ? null
          : Timestamp.fromDate(dateOfBirth!),
      'weightKg': weightKg,
      'photoUrl': photoUrl.trim(),
      'bio': bio.trim(),
      'isVaccinated': isVaccinated,
      'vaccinationDate': isVaccinated && vaccinationDate != null
          ? Timestamp.fromDate(vaccinationDate!)
          : null,
      'isDewormed': isDewormed,
      'dewormingDate': isDewormed && dewormingDate != null
          ? Timestamp.fromDate(dewormingDate!)
          : null,
      'knownAllergies': knownAllergies.trim(),
      'regularVet': regularVet.trim(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'isDeleted': isDeleted,
    };
  }

  PetProfile copyWith({
    String? id,
    String? ownerId,
    String? name,
    String? animalType,
    String? sex,
    String? breed,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
    double? weightKg,
    bool clearWeightKg = false,
    String? photoUrl,
    String? bio,
    bool? isVaccinated,
    DateTime? vaccinationDate,
    bool clearVaccinationDate = false,
    bool? isDewormed,
    DateTime? dewormingDate,
    bool clearDewormingDate = false,
    String? knownAllergies,
    String? regularVet,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isDeleted,
  }) {
    return PetProfile(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      animalType: animalType ?? this.animalType,
      sex: sex ?? this.sex,
      breed: breed ?? this.breed,
      dateOfBirth: clearDateOfBirth ? null : dateOfBirth ?? this.dateOfBirth,
      weightKg: clearWeightKg ? null : weightKg ?? this.weightKg,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      isVaccinated: isVaccinated ?? this.isVaccinated,
      vaccinationDate: clearVaccinationDate
          ? null
          : vaccinationDate ?? this.vaccinationDate,
      isDewormed: isDewormed ?? this.isDewormed,
      dewormingDate: clearDewormingDate
          ? null
          : dewormingDate ?? this.dewormingDate,
      knownAllergies: knownAllergies ?? this.knownAllergies,
      regularVet: regularVet ?? this.regularVet,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  static DateTime? _readDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    try {
      return (value as dynamic)?.toDate() as DateTime?;
    } catch (_) {
      return null;
    }
  }
}
