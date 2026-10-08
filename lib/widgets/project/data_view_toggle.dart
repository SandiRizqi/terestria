import 'package:flutter/material.dart';

import '../../services/data_view_mode_store.dart';
import '../../theme/app_theme.dart';

/// Tombol pilih tampilan data project: grid atau list.
class DataViewToggle extends StatelessWidget {
  final DataViewMode mode;
  final ValueChanged<DataViewMode> onChanged;

  const DataViewToggle({super.key, required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _button(DataViewMode.grid, Icons.grid_view_rounded, 'Grid view'),
          _button(DataViewMode.list, Icons.view_list_rounded, 'List view'),
        ],
      ),
    );
  }

  Widget _button(DataViewMode value, IconData icon, String label) {
    final selected = mode == value;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primaryGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
