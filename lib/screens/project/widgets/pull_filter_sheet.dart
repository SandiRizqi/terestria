import 'package:flutter/material.dart';

/// Bottom sheet untuk menyusun filter dinamis sebelum pull data dari server.
///
/// Key filter dipilih dari [fieldKeys] (label field project). User bisa
/// menambah/menghapus baris `key = value`. Saat submit, hanya baris dengan key
/// terpilih DAN value tidak kosong yang dikirim ke [onSubmit] (AND semua baris).
/// Filter kosong diperbolehkan (pull semua — tetap lewat preflight count).
class PullFilterSheet extends StatefulWidget {
  final List<String> fieldKeys;
  final void Function(Map<String, String> filters) onSubmit;

  const PullFilterSheet({
    super.key,
    required this.fieldKeys,
    required this.onSubmit,
  });

  @override
  State<PullFilterSheet> createState() => _PullFilterSheetState();
}

class _FilterRow {
  String? key;
  final TextEditingController value = TextEditingController();
}

class _PullFilterSheetState extends State<PullFilterSheet> {
  final List<_FilterRow> _rows = [_FilterRow()];

  @override
  void dispose() {
    for (final r in _rows) {
      r.value.dispose();
    }
    super.dispose();
  }

  void _addRow() => setState(() => _rows.add(_FilterRow()));

  void _removeRow(int i) => setState(() {
        _rows[i].value.dispose();
        _rows.removeAt(i);
        if (_rows.isEmpty) _rows.add(_FilterRow());
      });

  void _submit() {
    final filters = <String, String>{};
    for (final r in _rows) {
      final k = r.key;
      final v = r.value.text.trim();
      if (k != null && k.isNotEmpty && v.isNotEmpty) {
        filters[k] = v;
      }
    }
    widget.onSubmit(filters);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined),
                const SizedBox(width: 8),
                Text('Filter Data (Pull)',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Pilih field & nilai (cocok sebagian / contains). Kosongkan untuk menarik semua.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (int i = 0; i < _rows.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: DropdownButtonFormField<String>(
                                key: ValueKey('filter-key-$i'),
                                value: _rows[i].key,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Field',
                                  border: OutlineInputBorder(),
                                  contentPadding:
                                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                items: widget.fieldKeys
                                    .map((k) => DropdownMenuItem(
                                        value: k, child: Text(k)))
                                    .toList(),
                                onChanged: (v) => setState(() => _rows[i].key = v),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 5,
                              child: TextField(
                                key: ValueKey('filter-value-$i'),
                                controller: _rows[i].value,
                                decoration: const InputDecoration(
                                  labelText: 'Nilai',
                                  border: OutlineInputBorder(),
                                  contentPadding:
                                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                              ),
                            ),
                            IconButton(
                              key: ValueKey('filter-remove-$i'),
                              tooltip: 'Hapus',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => _removeRow(i),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('pull-filter-add-row'),
                onPressed: _addRow,
                icon: const Icon(Icons.add),
                label: const Text('Tambah filter'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('pull-filter-submit'),
              onPressed: _submit,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Cek & Download'),
            ),
          ],
        ),
      ),
    );
  }
}
