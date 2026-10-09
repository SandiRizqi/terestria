import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/project_list.dart';

/// Kotak cari & chip filter daftar project (template "Projects list").

class ProjectSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const ProjectSearchField(
      {super.key, required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.grey.shade300),
    );
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search projects...',
          prefixIcon:
              const Icon(Icons.search_rounded, color: AppTheme.textSecondary),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: AppTheme.cardBackground,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide:
                const BorderSide(color: AppTheme.primaryGreen, width: 2),
          ),
        ),
      ),
    );
  }
}

/// Chip "All n / Unsynced / From server".
class ProjectFilterChips extends StatelessWidget {
  final ProjectListFilter selected;
  final int allCount;
  final ValueChanged<ProjectListFilter> onSelected;

  const ProjectFilterChips({
    super.key,
    required this.selected,
    required this.allCount,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _chip(ProjectListFilter.all, 'All $allCount'),
          const SizedBox(width: 8),
          _chip(ProjectListFilter.unsynced, 'Unsynced'),
          const SizedBox(width: 8),
          _chip(ProjectListFilter.fromServer, 'From server'),
        ],
      ),
    );
  }

  Widget _chip(ProjectListFilter value, String label) {
    final active = selected == value;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      showCheckmark: false,
      onSelected: (_) => onSelected(value),
      selectedColor: AppTheme.textPrimary,
      backgroundColor: AppTheme.cardBackground,
      side: BorderSide(
          color: active ? AppTheme.textPrimary : Colors.grey.shade300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: active ? Colors.white : AppTheme.textPrimary,
      ),
    );
  }
}
