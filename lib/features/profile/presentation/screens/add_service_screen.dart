import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../../../core/widgets/glass_surface.dart';
import '../../domain/models/service_details_draft.dart';
import 'add_service_booking_setup_screen.dart';

class AddServiceScreen extends StatefulWidget {
  const AddServiceScreen({super.key});

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  static const Color _screenBackground = Color(0xFFFCF8F5);
  static const List<String> _animalOptions = [
    'Dog',
    'Cat',
    'Bird',
    'Rabbit',
    'Fish',
    'Guinea Pig',
    'Hamster',
    'Turtle / Tortoise',
    'Lizard / Reptile',
    'Other',
  ];

  static const Map<String, List<String>> _categoryOptionsByAnimal = {
    'Dog': [
      'Walking',
      'Grooming',
      'Training',
      'Boarding',
      'Sitting',
      'Vet Visit',
      'Nail Trimming',
      'Bath & Brush',
      'Other',
    ],
    'Cat': [
      'Grooming',
      'Boarding',
      'Sitting',
      'Vet Visit',
      'Nail Trimming',
      'Other',
    ],
    'Bird': [
      'Grooming',
      'Sitting',
      'Vet Visit',
      'Wing Clipping',
      'Other',
    ],
    'Rabbit': ['Grooming', 'Sitting', 'Vet Visit', 'Other'],
    'Guinea Pig': ['Grooming', 'Sitting', 'Vet Visit', 'Other'],
    'Hamster': ['Grooming', 'Sitting', 'Vet Visit', 'Other'],
    'Fish': ['Tank Cleaning', 'Feeding Care', 'Vet Visit', 'Other'],
    'Lizard / Reptile': ['Sitting', 'Vet Visit', 'Other'],
    'Turtle / Tortoise': ['Sitting', 'Vet Visit', 'Other'],
    'Other': ['General Care', 'Sitting', 'Vet Visit', 'Other'],
  };

  static const Map<String, String> _serviceNameSuggestions = {
    'Dog|Walking': 'Daily Dog Walk',
    'Dog|Grooming': 'Dog Grooming Session',
    'Dog|Training': 'Dog Training Session',
    'Dog|Boarding': 'Dog Boarding',
    'Dog|Sitting': 'Dog Sitting',
    'Dog|Vet Visit': 'Dog Vet Visit',
    'Dog|Nail Trimming': 'Dog Nail Trimming',
    'Dog|Bath & Brush': 'Dog Bath & Brush',
    'Cat|Grooming': 'Cat Grooming Session',
    'Cat|Boarding': 'Cat Boarding',
    'Cat|Sitting': 'Cat Sitting',
    'Bird|Wing Clipping': 'Bird Wing Clipping',
    'Fish|Tank Cleaning': 'Fish Tank Cleaning',
  };

  final TextEditingController _animalController = TextEditingController();
  final TextEditingController _customAnimalController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _customCategoryController =
      TextEditingController();
  final TextEditingController _serviceNameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _animalFocusNode = FocusNode();
  final FocusNode _customAnimalFocusNode = FocusNode();
  final FocusNode _categoryFocusNode = FocusNode();
  final FocusNode _customCategoryFocusNode = FocusNode();
  final FocusNode _serviceNameFocusNode = FocusNode();
  final FocusNode _priceFocusNode = FocusNode();
  final FocusNode _descriptionFocusNode = FocusNode();
  final GlobalKey _animalFieldKey = GlobalKey();
  final GlobalKey _customAnimalFieldKey = GlobalKey();
  final GlobalKey _categoryFieldKey = GlobalKey();
  final GlobalKey _customCategoryFieldKey = GlobalKey();
  final GlobalKey _serviceNameFieldKey = GlobalKey();
  final GlobalKey _priceFieldKey = GlobalKey();
  final GlobalKey _descriptionFieldKey = GlobalKey();

  String? _selectedAnimal;
  String? _selectedCategory;

  String? _animalError;
  String? _customAnimalError;
  String? _categoryError;
  String? _customCategoryError;
  String? _serviceNameError;
  String? _priceError;
  String? _descriptionError;

  bool _isApplyingSuggestion = false;
  String _lastSuggestedServiceName = '';
  _ServiceDetailsField? _highlightedField;

  bool get _isOtherAnimal => _selectedAnimal == 'Other';
  bool get _isOtherCategory => _selectedCategory == 'Other';

  List<String> get _categoryOptions {
    if (_selectedAnimal == null) return const [];
    return _categoryOptionsByAnimal[_selectedAnimal] ?? const [];
  }

  bool get _isFormValid {
    final animal = _selectedAnimal;
    final category = _selectedCategory;
    final customAnimal = _customAnimalController.text.trim();
    final customCategory = _customCategoryController.text.trim();
    final serviceName = _serviceNameController.text.trim();
    final description = _descriptionController.text.trim();
    final price = int.tryParse(_priceController.text.trim());

    return animal != null &&
        (!_isOtherAnimal || customAnimal.isNotEmpty) &&
        category != null &&
        (!_isOtherCategory || customCategory.isNotEmpty) &&
        serviceName.isNotEmpty &&
        serviceName.length <= 60 &&
        price != null &&
        price >= 1 &&
        price <= 99999 &&
        description.length >= 30 &&
        description.length <= 500;
  }

  @override
  void initState() {
    super.initState();
    _serviceNameController.addListener(_handleServiceNameEdit);
  }

  void _handleServiceNameEdit() {
    if (_isApplyingSuggestion) return;
    final currentText = _serviceNameController.text.trim();
    if (currentText != _lastSuggestedServiceName) {
      _serviceNameError = null;
    }
  }

  @override
  void dispose() {
    _animalController.dispose();
    _customAnimalController.dispose();
    _categoryController.dispose();
    _customCategoryController.dispose();
    _serviceNameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _animalFocusNode.dispose();
    _customAnimalFocusNode.dispose();
    _categoryFocusNode.dispose();
    _customCategoryFocusNode.dispose();
    _serviceNameFocusNode.dispose();
    _priceFocusNode.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  void _onAnimalSelected(String value) {
    if (_selectedAnimal == value) return;

    // Category depends on animal type, so we reset it whenever the animal
    // changes to avoid leaving a stale category selected.
    setState(() {
      _selectedAnimal = value;
      _animalController.text = value;
      _selectedCategory = null;
      _categoryController.clear();
      _customAnimalController.clear();
      _customCategoryController.clear();
      _animalError = null;
      _customAnimalError = null;
      _categoryError = null;
      _customCategoryError = null;
      _clearHighlight();
    });

    _applyServiceNameSuggestion();
  }

  void _onCategorySelected(String value) {
    setState(() {
      _selectedCategory = value;
      _categoryController.text = value;
      _customCategoryController.clear();
      _categoryError = null;
      _customCategoryError = null;
      _clearHighlight();
    });

    _applyServiceNameSuggestion();
  }

  void _applyServiceNameSuggestion() {
    final animal = _selectedAnimal;
    final category = _selectedCategory;
    if (animal == null || category == null) return;

    final suggestion = _serviceNameSuggestions['$animal|$category'] ?? '';
    final currentText = _serviceNameController.text.trim();

    // Only overwrite when the field is empty or still matches the last
    // generated suggestion, so manual edits always stay under user control.
    final canReplace =
        currentText.isEmpty || currentText == _lastSuggestedServiceName;

    if (!canReplace) {
      _lastSuggestedServiceName = suggestion;
      return;
    }

    _isApplyingSuggestion = true;
    _serviceNameController.text = suggestion;
    _serviceNameController.selection = TextSelection.collapsed(
      offset: _serviceNameController.text.length,
    );
    _isApplyingSuggestion = false;
    _lastSuggestedServiceName = suggestion;
    setState(() {
      _serviceNameError = null;
    });
  }

  bool _validateForm() {
    final serviceName = _serviceNameController.text.trim();
    final description = _descriptionController.text.trim();
    final priceValue = int.tryParse(_priceController.text.trim());

    setState(() {
      _animalError = _selectedAnimal == null ? 'Animal type is required' : null;
      _customAnimalError = _isOtherAnimal &&
              _customAnimalController.text.trim().isEmpty
          ? 'Please specify the animal'
          : null;
      _categoryError = _selectedCategory == null ? 'Category is required' : null;
      _customCategoryError = _isOtherCategory &&
              _customCategoryController.text.trim().isEmpty
          ? 'Please enter a custom category'
          : null;
      _serviceNameError = serviceName.isEmpty
          ? 'Service name is required'
          : serviceName.length > 60
          ? 'Service name must be 60 characters or less'
          : null;
      _priceError = priceValue == null || priceValue < 1 || priceValue > 99999
          ? 'Price must be between ₹1 and ₹99,999'
          : null;
      _descriptionError = description.isEmpty
          ? 'Description is required'
          : description.length < 30
          ? 'Description must be at least 30 characters'
          : description.length > 500
          ? 'Description must be 500 characters or less'
          : null;
    });

    return _isFormValid;
  }

  void _clearHighlight() {
    if (_highlightedField == null) return;
    _highlightedField = null;
  }

  _FieldIssue? _firstInvalidField() {
    final serviceName = _serviceNameController.text.trim();
    final description = _descriptionController.text.trim();
    final priceValue = int.tryParse(_priceController.text.trim());

    if (_selectedAnimal == null) {
      return _FieldIssue(
        field: _ServiceDetailsField.animal,
        key: _animalFieldKey,
        focusNode: _animalFocusNode,
        message: 'Select which animal this service is for.',
      );
    }

    if (_isOtherAnimal && _customAnimalController.text.trim().isEmpty) {
      return _FieldIssue(
        field: _ServiceDetailsField.customAnimal,
        key: _customAnimalFieldKey,
        focusNode: _customAnimalFocusNode,
        message: 'Specify the animal so people know what this service covers.',
      );
    }

    if (_selectedCategory == null) {
      return _FieldIssue(
        field: _ServiceDetailsField.category,
        key: _categoryFieldKey,
        focusNode: _categoryFocusNode,
        message: 'Choose a category for this service.',
      );
    }

    if (_isOtherCategory && _customCategoryController.text.trim().isEmpty) {
      return _FieldIssue(
        field: _ServiceDetailsField.customCategory,
        key: _customCategoryFieldKey,
        focusNode: _customCategoryFocusNode,
        message: 'Add a custom category name before continuing.',
      );
    }

    if (serviceName.isEmpty) {
      return _FieldIssue(
        field: _ServiceDetailsField.serviceName,
        key: _serviceNameFieldKey,
        focusNode: _serviceNameFocusNode,
        message: 'Enter a service name.',
      );
    }

    if (serviceName.length > 60) {
      return _FieldIssue(
        field: _ServiceDetailsField.serviceName,
        key: _serviceNameFieldKey,
        focusNode: _serviceNameFocusNode,
        message: 'Service name must be 60 characters or less.',
      );
    }

    if (priceValue == null || priceValue < 1 || priceValue > 99999) {
      return _FieldIssue(
        field: _ServiceDetailsField.price,
        key: _priceFieldKey,
        focusNode: _priceFocusNode,
        message: 'Price must be between ₹1 and ₹99,999.',
      );
    }

    if (description.isEmpty) {
      return _FieldIssue(
        field: _ServiceDetailsField.description,
        key: _descriptionFieldKey,
        focusNode: _descriptionFocusNode,
        message: 'Add a description before continuing.',
      );
    }

    if (description.length < 30) {
      final remaining = 30 - description.length;
      return _FieldIssue(
        field: _ServiceDetailsField.description,
        key: _descriptionFieldKey,
        focusNode: _descriptionFocusNode,
        message:
            'Description needs $remaining more character${remaining == 1 ? '' : 's'} to continue.',
      );
    }

    if (description.length > 500) {
      return _FieldIssue(
        field: _ServiceDetailsField.description,
        key: _descriptionFieldKey,
        focusNode: _descriptionFocusNode,
        message: 'Description must be 500 characters or less.',
      );
    }

    return null;
  }

  Future<void> _showFieldGuidance(_FieldIssue issue) async {
    setState(() {
      _highlightedField = issue.field;
    });

    AppFeedback.show(
      context,
      message: issue.message,
      tone: AppFeedbackTone.info,
    );

    final fieldContext = issue.key.currentContext;
    if (fieldContext != null) {
      await Scrollable.ensureVisible(
        fieldContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    }

    issue.focusNode.requestFocus();
  }

  Future<void> _handleNextPress() async {
    if (_validateForm()) {
      await _goToNext();
      return;
    }

    final issue = _firstInvalidField();
    if (issue != null) {
      await _showFieldGuidance(issue);
    }
  }

  Future<void> _goToNext() async {
    if (!_validateForm()) return;

    final draft = ServiceDetailsDraft(
      animalType: _selectedAnimal!,
      customAnimalType: _isOtherAnimal ? _customAnimalController.text.trim() : null,
      category: _selectedCategory!,
      customCategory:
          _isOtherCategory ? _customCategoryController.text.trim() : null,
      serviceName: _serviceNameController.text.trim(),
      pricePerSession: int.parse(_priceController.text.trim()),
      description: _descriptionController.text.trim(),
    );

    final published = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddServiceBookingSetupScreen(draft: draft),
      ),
    );

    if (published == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final topContentPadding = topInset + 108;

    return Scaffold(
      backgroundColor: _screenBackground,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            // The form is rendered first so it can scroll behind the floating
            // glass header while still reserving safe top spacing.
            ListView(
              padding: EdgeInsets.fromLTRB(
                18,
                topContentPadding,
                18,
                bottomInset + 28,
              ),
              children: [
                _FormSectionCard(
                  title: 'Service Details',
                  subtitle:
                      'Define the service clearly so pet parents understand exactly what they are booking.',
                  children: [
                    _SearchableDropdownField(
                      fieldKey: _animalFieldKey,
                      label: 'Which animal is this service for?',
                      controller: _animalController,
                      focusNode: _animalFocusNode,
                      options: _animalOptions,
                      errorText: _animalError,
                      isHighlighted: _highlightedField == _ServiceDetailsField.animal,
                      noResultsText:
                          'Not listed? Select Other and type your animal below.',
                      onSelected: _onAnimalSelected,
                      onChanged: () {
                        setState(() {
                          _animalError = null;
                          if (_highlightedField == _ServiceDetailsField.animal) {
                            _clearHighlight();
                          }
                        });
                      },
                    ),
                    if (_isOtherAnimal) ...[
                      const SizedBox(height: 14),
                      _ServiceTextField(
                        fieldKey: _customAnimalFieldKey,
                        controller: _customAnimalController,
                        focusNode: _customAnimalFocusNode,
                        label: 'Specify animal',
                        hintText: 'e.g. Monkey, Parrot, Snake',
                        errorText: _customAnimalError,
                        isHighlighted:
                            _highlightedField == _ServiceDetailsField.customAnimal,
                        maxLength: 30,
                        onChanged: (_) {
                          setState(() {
                            _customAnimalError = null;
                            if (_highlightedField ==
                                _ServiceDetailsField.customAnimal) {
                              _clearHighlight();
                            }
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (_selectedAnimal != null)
                      _SearchableDropdownField(
                        fieldKey: _categoryFieldKey,
                        label: 'Category',
                        controller: _categoryController,
                        focusNode: _categoryFocusNode,
                        options: _categoryOptions,
                        hintText: 'Select a category',
                        errorText: _categoryError,
                        isHighlighted:
                            _highlightedField == _ServiceDetailsField.category,
                        onSelected: _onCategorySelected,
                        onChanged: () {
                          setState(() {
                            _categoryError = null;
                            if (_highlightedField ==
                                _ServiceDetailsField.category) {
                              _clearHighlight();
                            }
                          });
                        },
                      ),
                    if (_isOtherCategory) ...[
                      const SizedBox(height: 14),
                      _ServiceTextField(
                        fieldKey: _customCategoryFieldKey,
                        controller: _customCategoryController,
                        focusNode: _customCategoryFocusNode,
                        label: 'Custom category',
                        hintText: 'e.g. Pet taxi, Aquarium cleaning',
                        errorText: _customCategoryError,
                        isHighlighted: _highlightedField ==
                            _ServiceDetailsField.customCategory,
                        maxLength: 30,
                        onChanged: (_) {
                          setState(() {
                            _customCategoryError = null;
                            if (_highlightedField ==
                                _ServiceDetailsField.customCategory) {
                              _clearHighlight();
                            }
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 14),
                    _ServiceTextField(
                      fieldKey: _serviceNameFieldKey,
                      controller: _serviceNameController,
                      focusNode: _serviceNameFocusNode,
                      label: 'Service name',
                      hintText:
                          'e.g. Dog grooming, Cat boarding, Daily dog walk',
                      errorText: _serviceNameError,
                      isHighlighted:
                          _highlightedField == _ServiceDetailsField.serviceName,
                      maxLength: 60,
                      onChanged: (_) {
                        setState(() {
                          _serviceNameError = null;
                          if (_highlightedField ==
                              _ServiceDetailsField.serviceName) {
                            _clearHighlight();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    _ServiceTextField(
                      fieldKey: _priceFieldKey,
                      controller: _priceController,
                      focusNode: _priceFocusNode,
                      label: 'Price per session',
                      hintText: 'Enter amount',
                      prefixText: '₹ ',
                      helperText:
                          'This is the full price paid upfront by the pet parent.',
                      errorText: _priceError,
                      isHighlighted:
                          _highlightedField == _ServiceDetailsField.price,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) {
                        setState(() {
                          _priceError = null;
                          if (_highlightedField == _ServiceDetailsField.price) {
                            _clearHighlight();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 14),
                    _ServiceTextField(
                      fieldKey: _descriptionFieldKey,
                      controller: _descriptionController,
                      focusNode: _descriptionFocusNode,
                      label: 'Description',
                      hintText:
                          "Describe what's included, who it's for, and any important details.",
                      helperText:
                          'This helps pet parents understand your service before booking.',
                      errorText: _descriptionError,
                      isHighlighted:
                          _highlightedField == _ServiceDetailsField.description,
                      maxLines: 6,
                      maxLength: 500,
                      showCounter: true,
                      onChanged: (_) {
                        setState(() {
                          _descriptionError = null;
                          if (_highlightedField ==
                              _ServiceDetailsField.description) {
                            _clearHighlight();
                          }
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Stack(
                  children: [
                    GradientButton(
                      label: 'Next',
                      onPressed: _isFormValid ? _handleNextPress : null,
                    ),
                    if (!_isFormValid)
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _handleNextPress,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 16,
              right: 16,
              top: topInset + 10,
              child: GlassSurface(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                borderRadius: BorderRadius.circular(24),
                backgroundColor: Colors.white.withValues(alpha: 0.72),
                blurSigma: 20,
                border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.56),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Service Details',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormSectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _FormSectionCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _ServiceTextField extends StatelessWidget {
  final Key? fieldKey;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String hintText;
  final String? helperText;
  final String? errorText;
  final String? prefixText;
  final bool isHighlighted;
  final int maxLines;
  final int? maxLength;
  final bool showCounter;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  const _ServiceTextField({
    this.fieldKey,
    required this.controller,
    this.focusNode,
    required this.label,
    required this.hintText,
    this.helperText,
    this.errorText,
    this.prefixText,
    this.isHighlighted = false,
    this.maxLines = 1,
    this.maxLength,
    this.showCounter = false,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final counterText = showCounter && maxLength != null
        ? '${controller.text.length} / $maxLength'
        : null;

    return Column(
      key: fieldKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hintText,
            helperText: helperText,
            errorText: errorText,
            prefixText: prefixText,
            counterText: counterText,
            filled: true,
            fillColor: const Color(0xFFFCFBFA),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: isHighlighted
                  ? const BorderSide(color: AppColors.primary, width: 1.6)
                  : BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: isHighlighted
                  ? const BorderSide(color: AppColors.primary, width: 1.6)
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchableDropdownField extends StatefulWidget {
  final Key? fieldKey;
  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final List<String> options;
  final String? hintText;
  final String? errorText;
  final bool isHighlighted;
  final String? noResultsText;
  final ValueChanged<String> onSelected;
  final VoidCallback? onChanged;

  const _SearchableDropdownField({
    this.fieldKey,
    required this.label,
    required this.controller,
    this.focusNode,
    required this.options,
    required this.onSelected,
    this.hintText,
    this.errorText,
    this.isHighlighted = false,
    this.noResultsText,
    this.onChanged,
  });

  @override
  State<_SearchableDropdownField> createState() =>
      _SearchableDropdownFieldState();
}

class _SearchableDropdownFieldState extends State<_SearchableDropdownField> {
  late final FocusNode _focusNode;
  late final bool _ownsFocusNode;
  bool _isExpanded = false;

  List<String> get _filteredOptions {
    final query = widget.controller.text.trim().toLowerCase();
    if (query.isEmpty) return widget.options;
    return widget.options
        .where((option) => option.toLowerCase().contains(query))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) return;
      setState(() {
        _isExpanded = true;
      });
    });
  }

  @override
  void dispose() {
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _selectOption(String value) {
    widget.controller.text = value;
    widget.controller.selection = TextSelection.collapsed(offset: value.length);
    widget.onSelected(value);
    setState(() {
      _isExpanded = false;
    });
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final filteredOptions = _filteredOptions;

    return Column(
      key: widget.fieldKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: const TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          focusNode: _focusNode,
          onTap: () => setState(() => _isExpanded = true),
          onChanged: (_) {
            setState(() => _isExpanded = true);
            widget.onChanged?.call();
          },
          decoration: InputDecoration(
            hintText: widget.hintText,
            errorText: widget.errorText,
            filled: true,
            fillColor: const Color(0xFFFCFBFA),
            suffixIcon: Icon(
              _isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: AppColors.textGrey,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: widget.isHighlighted
                  ? const BorderSide(color: AppColors.primary, width: 1.6)
                  : BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: widget.isHighlighted
                  ? const BorderSide(color: AppColors.primary, width: 1.6)
                  : BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
            ),
          ),
        ),
        if (_isExpanded) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: filteredOptions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      widget.noResultsText ?? 'No matching options found.',
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    shrinkWrap: true,
                    itemCount: filteredOptions.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: AppColors.primary.withValues(alpha: 0.06),
                    ),
                    itemBuilder: (context, index) {
                      final option = filteredOptions[index];
                      return ListTile(
                        title: Text(
                          option,
                          style: const TextStyle(
                            color: AppColors.textDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () => _selectOption(option),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }
}

enum _ServiceDetailsField {
  animal,
  customAnimal,
  category,
  customCategory,
  serviceName,
  price,
  description,
}

class _FieldIssue {
  final _ServiceDetailsField field;
  final GlobalKey key;
  final FocusNode focusNode;
  final String message;

  const _FieldIssue({
    required this.field,
    required this.key,
    required this.focusNode,
    required this.message,
  });
}
