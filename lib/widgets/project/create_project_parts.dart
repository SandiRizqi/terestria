import 'package:flutter/material.dart';

import '../../models/field_type_info.dart';
import '../../models/form_field_model.dart';
import '../../models/project_model.dart';
import '../../theme/app_theme.dart';
import '../../utils/field_values.dart' show formatNumber;

/// Potongan layar buat/edit project mengikuti template "New project · custom
/// columns": label bagian, pilihan geometri bergaya segmented, kartu field
/// berlencana tipe, dan tombol tambah bergaris putus. Warna dari [AppTheme].

/// Label kecil di atas isian ("Project Name", "Geometry Type").
class FormSectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const FormSectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Point | Line | Polygon. [onChanged] null = tidak bisa diubah (edit project).
class GeometrySegmentedControl extends StatelessWidget {
  final GeometryType value;
  final ValueChanged<GeometryType>? onChanged;

  const GeometrySegmentedControl(
      {super.key, required this.value, required this.onChanged});

  static const _labels = {
    GeometryType.point: 'Point',
    GeometryType.line: 'Line',
    GeometryType.polygon: 'Polygon',
  };

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.inputBackground,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            for (final type in GeometryType.values)
              Expanded(child: _segment(type, enabled)),
          ],
        ),
      ),
    );
  }

  Widget _segment(GeometryType type, bool enabled) {
    final selected = type == value;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(type) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppTheme.cardBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            _labels[type]!,
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppTheme.primaryGreen : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Baris kedua kartu field: opsi, batas angka, jumlah foto; selain itu
/// "Required" atau keterangan tipe. Ditambah "Unique key" bila field kunci.
String fieldCardSubtitle(FormFieldModel field, {required bool isUniqueKey}) {
  String? detail;
  final options = field.options;
  final isChoice =
      field.type == FieldType.dropdown || field.type == FieldType.multiselect;
  final isNumber =
      field.type == FieldType.number || field.type == FieldType.decimal;
  if (isChoice && options != null && options.isNotEmpty) {
    detail = options.join(', ');
  } else if (isNumber && (field.min != null || field.max != null)) {
    final unit = (field.unit ?? '').isEmpty ? '' : ' ${field.unit}';
    if (field.min != null && field.max != null) {
      detail = '${formatNumber(field.min!)}–${formatNumber(field.max!)}$unit';
    } else if (field.min != null) {
      detail = '≥ ${formatNumber(field.min!)}$unit';
    } else {
      detail = '≤ ${formatNumber(field.max!)}$unit';
    }
  } else if (field.type == FieldType.photo &&
      (field.minPhotos != null || field.maxPhotos != null)) {
    detail = [
      if (field.minPhotos != null) 'Min ${field.minPhotos}',
      if (field.maxPhotos != null)
        field.minPhotos != null ? 'max ${field.maxPhotos}' : 'Max ${field.maxPhotos}',
    ].join(' · ');
  }
  detail ??= field.required
      ? 'Required'
      : field.isUnknownType
          ? fieldTypeDisplayName(field)
          : fieldTypeInfo(field.type).description;
  return isUniqueKey ? '$detail · Unique key' : detail;
}

/// Kartu satu field form: pegangan seret (opsional), label (+ * wajib),
/// ringkasan, lencana tipe, dan tombol hapus.
class FormFieldCard extends StatelessWidget {
  final FormFieldModel field;
  final bool isUniqueKey;

  /// Pegangan seret (mis. `ReorderableDragStartListener`); null = tidak bisa
  /// diurutkan.
  final Widget? dragHandle;

  /// Null = field tidak bisa diubah/dihapus (edit project).
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const FormFieldCard({
    super.key,
    required this.field,
    required this.isUniqueKey,
    this.dragHandle,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final typeName =
        field.isUnknownType ? (field.unknownTypeName ?? 'unknown') : field.type.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.fromLTRB(dragHandle == null ? 16 : 6, 12, 8, 12),
            child: Row(
              children: [
                if (dragHandle != null) dragHandle!,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              field.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (field.required) ...[
                            const SizedBox(width: 3),
                            const Text(
                              '*',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.errorColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fieldCardSubtitle(field, isUniqueKey: isUniqueKey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    typeName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkGreen,
                    ),
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Delete field',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: AppTheme.errorColor,
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tombol "+ Add Field" dengan garis tepi putus-putus.
class DashedAddButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const DashedAddButton(
      {super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: AppTheme.primaryGreen, radius: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_rounded, color: AppTheme.primaryGreen),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, Radius.circular(radius)));
    const dash = 7.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
            metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
