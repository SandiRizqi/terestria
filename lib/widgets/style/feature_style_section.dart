import 'package:flutter/material.dart';

import '../../models/feature_style.dart';
import '../../models/layer_model.dart';
import '../../models/project_model.dart';
import 'style_editor.dart';

/// Bagian "Style" di form data survei & layar edit: style tampilan feature
/// ini. Tertutup → ringkasan ("Default"/"Custom" + swatch); dibuka → editor
/// sesuai geometri project. [style] null = ikut default ([defaultStyle], dari
/// Settings); perubahan pertama menjadikannya style custom.
class FeatureStyleSection extends StatefulWidget {
  final GeometryType geometryType;
  final LayerStyle? style;
  final LayerStyle defaultStyle;

  /// Style baru; null = kembali ke default.
  final ValueChanged<LayerStyle?> onChanged;

  const FeatureStyleSection({
    super.key,
    required this.geometryType,
    required this.style,
    required this.defaultStyle,
    required this.onChanged,
  });

  @override
  State<FeatureStyleSection> createState() => _FeatureStyleSectionState();
}

class _FeatureStyleSectionState extends State<FeatureStyleSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final custom = widget.style != null;
    final effective = clampFeatureStyle(widget.style ?? widget.defaultStyle);
    final geometry = styleGeometryForProject(widget.geometryType);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Row(
                children: [
                  _StyleSwatch(style: effective, geometry: geometry),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Style',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        Text(custom ? 'Custom' : 'Default',
                            style: TextStyle(
                                fontSize: 13, color: Colors.grey[700])),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StyleEditorFields(
                    style: effective,
                    geometry: geometry,
                    onChanged: widget.onChanged,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: custom ? () => widget.onChanged(null) : null,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Use default'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Contoh kecil style di ringkasan: lingkaran (point), garis (line), atau
/// kotak berisi dengan tepi (polygon).
class _StyleSwatch extends StatelessWidget {
  final LayerStyle style;
  final StyleGeometry geometry;
  const _StyleSwatch({required this.style, required this.geometry});

  @override
  Widget build(BuildContext context) {
    final fill = style.fillColor.withValues(alpha: style.fillOpacity);
    switch (geometry) {
      case StyleGeometry.point:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
          ),
        );
      case StyleGeometry.line:
        return SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Container(
              height: style.strokeWidth.clamp(2.0, 6.0).toDouble(),
              decoration: BoxDecoration(
                color:
                    style.strokeColor.withValues(alpha: style.fillOpacity),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        );
      case StyleGeometry.polygon:
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: style.strokeColor,
                width: style.strokeWidth.clamp(1.0, 3.0).toDouble()),
          ),
        );
    }
  }
}
