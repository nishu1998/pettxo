class ServiceDetailsDraft {
  final String animalType;
  final String? customAnimalType;
  final String category;
  final String? customCategory;
  final String serviceName;
  final int pricePerSession;
  final String description;

  const ServiceDetailsDraft({
    required this.animalType,
    this.customAnimalType,
    required this.category,
    this.customCategory,
    required this.serviceName,
    required this.pricePerSession,
    required this.description,
  });

  String get resolvedAnimalType =>
      animalType == 'Other' ? (customAnimalType?.trim() ?? '') : animalType;

  String get resolvedCategory =>
      category == 'Other' ? (customCategory?.trim() ?? '') : category;
}
