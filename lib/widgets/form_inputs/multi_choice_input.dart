import 'package:flutter/material.dart';

import '../../utils/field_values.dart';

/// Pilihan ganda: daftar centang dari [options]. Nilai tersimpan `"A; B"`
/// sesuai urutan opsi (kosong = `''`). Nilai lama yang sudah tidak ada di
/// daftar tetap tampil (ditandai) dan bisa dilepas. [onChanged] null =
/// baca-saja (mis. nilai di-pin).
class MultiChoiceInput extends StatelessWidget {
  final List<String> options;
  final Object? value;
  final ValueChanged<String>? onChanged;

  const MultiChoiceInput({
    super.key,
    required this.options,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = multiselectParts(value);
    final extra = [
      for (final s in selected)
        if (!options.contains(s)) s,
    ];

    void toggle(String option, bool on) {
      final next = [...selected.where((s) => s != option), if (on) option];
      onChanged!(joinMultiselect(next, options));
    }

    Widget tile(String option, {bool outdated = false}) => CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: selected.contains(option),
          onChanged:
              onChanged == null ? null : (on) => toggle(option, on ?? false),
          title: Text(
            outdated ? '$option (no longer in the list)' : option,
            style: outdated ? TextStyle(color: Colors.orange.shade800) : null,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final option in options) tile(option),
        for (final option in extra) tile(option, outdated: true),
      ],
    );
  }
}
