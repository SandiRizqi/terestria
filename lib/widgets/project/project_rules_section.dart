import 'package:flutter/material.dart';

import '../../models/field_type_info.dart';
import '../../models/form_field_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/field_values.dart' show parseLocaleNumber;

// Aturan project (SPEC §3.5) di pembuat project: akurasi minimum dan
// kombinasi unik. Field kunci dilacak lewat id (tahan ganti nama), disimpan
// sebagai label.

const double minAccuracyLow = 0.01;
const double minAccuracyHigh = 500;
const int maxUniqueFields = 5;

/// Akurasi minimum dari isian; null bila kosong (tanpa aturan) atau tidak valid.
double? minAccuracyFromInput(String text) {
  final value = parseLocaleNumber(text);
  if (value == null || value < minAccuracyLow || value > minAccuracyHigh) {
    return null;
  }
  return value;
}

/// Pesan untuk isian akurasi minimum; null bila kosong atau valid.
String? minAccuracyInputIssue(String text) {
  if (text.trim().isEmpty) return null;
  return minAccuracyFromInput(text) == null
      ? 'Must be between 0.01 and 500 m'
      : null;
}

/// [ids] yang masih ada di form dan memenuhi syarat field kunci (urutan tetap).
List<String> validUniqueFieldIds(List<FormFieldModel> fields, List<String> ids) => [
      for (final id in ids)
        if (fields.any((f) => f.id == id && canBeUniqueKey(f))) id,
    ];

/// Id field kunci dari label tersimpan; label yang tak ada/tak memenuhi
/// syarat dibuang.
List<String> uniqueFieldIdsFromLabels(
    List<FormFieldModel> fields, List<String> labels) {
  final ids = <String>[];
  for (final label in labels) {
    for (final field in fields) {
      if (field.label == label && canBeUniqueKey(field) && !ids.contains(field.id)) {
        ids.add(field.id);
        break;
      }
    }
  }
  return ids;
}

/// Label field kunci untuk disimpan (mengikuti label terbaru).
List<String> uniqueFieldLabels(List<FormFieldModel> fields, List<String> ids) => [
      for (final id in validUniqueFieldIds(fields, ids))
        fields.firstWhere((f) => f.id == id).label,
    ];

/// Field form dengan field kunci dijadikan wajib (SPEC: field kombinasi unik
/// otomatis wajib diisi).
List<FormFieldModel> withRequiredKeyFields(
        List<FormFieldModel> fields, List<String> ids) =>
    [
      for (final field in fields)
        ids.contains(field.id) && !field.required ? field.withRequired(true) : field,
    ];

class ProjectRulesSection extends StatelessWidget {
  final TextEditingController minAccuracyController;
  final List<FormFieldModel> fields;

  /// Id field kombinasi unik, berurutan.
  final List<String> uniqueFieldIds;
  final ValueChanged<List<String>> onUniqueFieldIdsChanged;

  const ProjectRulesSection({
    super.key,
    required this.minAccuracyController,
    required this.fields,
    required this.uniqueFieldIds,
    required this.onUniqueFieldIdsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: Colors.grey[700]);
    final selected = [
      for (final id in validUniqueFieldIds(fields, uniqueFieldIds))
        fields.firstWhere((f) => f.id == id),
    ];
    final available = [
      for (final field in fields)
        if (canBeUniqueKey(field) && !uniqueFieldIds.contains(field.id)) field,
    ];
    final full = selected.length >= maxUniqueFields;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Project rules',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: minAccuracyController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Minimum accuracy (m)',
            hintText: 'Optional, e.g. 5',
            helperText: 'GPS points less accurate than this are rejected for '
                'point projects and flagged for lines and polygons.',
            helperMaxLines: 3,
            errorMaxLines: 2,
            border: OutlineInputBorder(),
          ),
          validator: (value) => minAccuracyInputIssue(value ?? ''),
        ),
        const SizedBox(height: 16),
        const Text('Unique combination',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          selected.isEmpty
              ? 'Off — records may repeat the same values.'
              : '${selected.map((f) => f.label).join(' + ')} must be unique in '
                  'this project. These fields are always required.',
          style: muted,
        ),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final field in selected)
                InputChip(
                  label: Text(field.label, overflow: TextOverflow.ellipsis),
                  deleteButtonTooltipMessage:
                      'Remove ${field.label} from the combination',
                  onDeleted: () => onUniqueFieldIdsChanged([
                    for (final id in uniqueFieldIds)
                      if (id != field.id) id,
                  ]),
                ),
            ],
          ),
        ],
        MenuAnchor(
          menuChildren: [
            for (final field in available)
              MenuItemButton(
                onPressed: () =>
                    onUniqueFieldIdsChanged([...uniqueFieldIds, field.id]),
                child: Text(field.label),
              ),
          ],
          builder: (context, controller, _) => TextButton(
            onPressed: full || available.isEmpty
                ? null
                : () => controller.isOpen ? controller.close() : controller.open(),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 18),
                SizedBox(width: 4),
                Text('Add field'),
              ],
            ),
          ),
        ),
        if (full)
          Text('A combination can use at most $maxUniqueFields fields.',
              style: muted),
      ],
    );
  }
}
