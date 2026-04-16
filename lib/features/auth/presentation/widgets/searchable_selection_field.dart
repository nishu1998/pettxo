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

  const SearchableSelectionField({
    super.key,
    required this.labelText,
    required this.hintText,
    required this.options,
    required this.onSelected,
    this.value,
    this.errorText,
    this.enabled = true,
  });

  @override
  State<SearchableSelectionField> createState() =>
      _SearchableSelectionFieldState();
}

class _SearchableSelectionFieldState extends State<SearchableSelectionField> {
  bool _isFocused = false;

  Future<void> _openSelector() async {
    if (!widget.enabled) return;
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
          style: const TextStyle(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
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
        child: Container(
          height: MediaQuery.sizeOf(context).height * 0.72,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.black12,
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
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
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
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFDADADA)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFDADADA)),
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
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final option = _filteredOptions[index];
                          final isSelected = option == widget.selectedValue;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
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
                                ? const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.primary,
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
    );
  }
}
