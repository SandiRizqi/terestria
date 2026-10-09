import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// AppBar pengganti selama mode pilih di daftar data project: jumlah
/// terpilih, pilih/lepas semua, dan aksi untuk pilihan (mis. hapus).
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final int selectedCount;

  /// Semua record yang terlihat sudah terpilih.
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onToggleAll;
  final List<Widget> actions;

  const SelectionAppBar({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.onClose,
    required this.onToggleAll,
    this.actions = const [],
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.darkGreen,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close_rounded),
        onPressed: onClose,
      ),
      title: Text(
        '$selectedCount selected',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      actions: [
        IconButton(
          tooltip: allSelected ? 'Deselect all' : 'Select all',
          icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
          onPressed: onToggleAll,
        ),
        ...actions,
      ],
    );
  }
}
