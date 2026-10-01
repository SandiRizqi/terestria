import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Chip pilihan di panel filter daftar data (dropdown, pilihan ganda, skala):
/// pilih satu; ketuk yang terpilih untuk melepas (`onChanged(null)`).
class FilterOptionChips extends StatelessWidget {
  final List<String> values;
  final String? selected;
  final ValueChanged<String?> onChanged;

  /// Teks chip; bawaan = nilainya.
  final String Function(String value)? labelOf;

  const FilterOptionChips({
    super.key,
    required this.values,
    required this.selected,
    required this.onChanged,
    this.labelOf,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((value) {
        final isSelected = selected == value;
        return GestureDetector(
          onTap: () => onChanged(isSelected ? null : value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primaryGreen : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? AppTheme.primaryGreen : Colors.grey.shade300,
              ),
            ),
            child: Text(
              labelOf?.call(value) ?? value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
