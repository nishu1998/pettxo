import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';

class SearchableSelectionField extends StatefulWidget {
  final String labelText;
  final String hintText;
  final String? value;
  final String? errorText;
  final bool enabled;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final EdgeInsetsGeometry? contentPadding;
  final bool compactLabel;

  const SearchableSelectionField({
    super.key,
    required this.labelText,
    required this.hintText,
    required this.options,
    required this.onSelected,
    this.value,
    this.errorText,
    this.enabled = true,
    this.contentPadding,
    this.compactLabel = false,
  });

  @override
  State<SearchableSelectionField> createState() =>
      _SearchableSelectionFieldState();
}

class _SearchableSelectionFieldState extends State<SearchableSelectionField> {
  bool _isFocused = false;

  Future<void> _openSelector() async {
    if (!widget.enabled) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _isFocused = true;
    });

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _SelectionSheet(
          title: widget.labelText,
          options: widget.options,
          selectedValue: widget.value,
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _isFocused = false;
    });

    if (selected != null) {
      widget.onSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    const borderRadius = 12.0;
    final borderColor = widget.errorText != null
        ? Colors.redAccent
        : _isFocused
        ? AppColors.primary
        : const Color(0xFFDADADA);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.labelText,
          style: TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w500,
            fontSize: widget.compactLabel ? 13 : 14,
          ),
        ),
        SizedBox(height: widget.compactLabel ? 6 : 8),
        GestureDetector(
          onTap: _openSelector,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: InputDecorator(
              isEmpty: widget.value == null || widget.value!.isEmpty,
              decoration: InputDecoration(
                errorText: widget.errorText,
                filled: true,
                fillColor: widget.enabled ? Colors.white : Colors.grey.shade100,
                contentPadding:
                    widget.contentPadding ??
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(color: borderColor),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: const BorderSide(color: Color(0xFFDADADA)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.8,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      (widget.value == null || widget.value!.isEmpty)
                          ? widget.hintText
                          : widget.value!,
                      style: TextStyle(
                        color: widget.value == null || widget.value!.isEmpty
                            ? AppColors.textGrey
                            : AppColors.textDark,
                        fontWeight:
                            widget.value == null || widget.value!.isEmpty
                            ? FontWeight.w400
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: widget.enabled
                        ? AppColors.textGrey
                        : Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String? selectedValue;

  const _SelectionSheet({
    required this.title,
    required this.options,
    this.selectedValue,
  });

  @override
  State<_SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<_SelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  late List<String> _filteredOptions;

  @override
  void initState() {
    super.initState();
    _filteredOptions = widget.options;
    _searchController.addListener(_filterOptions);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterOptions);
    _searchController.dispose();
    super.dispose();
  }

  void _filterOptions() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredOptions = widget.options
          .where((option) => option.toLowerCase().contains(query))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: MediaQuery.sizeOf(context).height * 0.72,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.62)),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.82),
                    const Color(0xFFFFF8F2).withValues(alpha: 0.72),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 48,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.66),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.74),
                          ),
                        ),
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          splashRadius: 16,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(
                            minWidth: 34,
                            minHeight: 34,
                          ),
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search ${widget.title.toLowerCase()}',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.74),
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.68),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.68),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.8,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: _filteredOptions.isEmpty
                        ? const Center(
                            child: Text(
                              'No results found',
                              style: TextStyle(color: AppColors.textGrey),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _filteredOptions.length,
                            separatorBuilder: (_, _) => Divider(
                              height: 1,
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                            itemBuilder: (context, index) {
                              final option = _filteredOptions[index];
                              final isSelected = option == widget.selectedValue;
                              return ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                title: Text(
                                  option,
                                  style: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: AppColors.textDark,
                                  ),
                                ),
                                trailing: isSelected
                                    ? Container(
                                        width: 28,
                                        height: 28,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            9,
                                          ),
                                          border: Border.all(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.22,
                                            ),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.check_rounded,
                                          color: AppColors.primary,
                                          size: 18,
                                        ),
                                      )
                                    : null,
                                onTap: () => Navigator.pop(context, option),
                              );
                            },
                          ),
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
