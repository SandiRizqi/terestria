import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../models/feature_style.dart';
import '../../models/layer_model.dart';
import '../../models/project_model.dart';

/// Editor style bersama — dipakai editor Layers (layer impor) dan bagian Style
/// di form data survei (style per feature). Dipindahkan dari
/// `layers_screen.dart` tanpa perubahan perilaku.

/// Jenis geometri untuk menentukan kontrol yang tampil.
enum StyleGeometry { point, line, polygon }

/// Geometri layer impor ('Point', 'LineString', 'Polygon', 'Mixed'); selain
/// point & line diperlakukan seperti polygon (perilaku editor Layers).
StyleGeometry styleGeometryForLayer(String layerGeometryType) {
  switch (layerGeometryType) {
    case 'Point':
      return StyleGeometry.point;
    case 'LineString':
      return StyleGeometry.line;
    default:
      return StyleGeometry.polygon;
  }
}

StyleGeometry styleGeometryForProject(GeometryType type) {
  switch (type) {
    case GeometryType.point:
      return StyleGeometry.point;
    case GeometryType.line:
      return StyleGeometry.line;
    case GeometryType.polygon:
      return StyleGeometry.polygon;
  }
}

/// Kontrol style sesuai [geometry]: warna (polygon: + warna tepi), opacity,
/// tebal garis (bukan point), ukuran point (point saja), dan pratinjau.
class StyleEditorFields extends StatelessWidget {
  final LayerStyle style;
  final StyleGeometry geometry;
  final ValueChanged<LayerStyle> onChanged;

  const StyleEditorFields({
    super.key,
    required this.style,
    required this.geometry,
    required this.onChanged,
  });

  void _pickColor(
      BuildContext context, Color current, ValueChanged<Color> onPicked) {
    Color temp = current;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Pick Color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: temp,
            onColorChanged: (c) => temp = c,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              onPicked(temp);
              Navigator.pop(dialogContext);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPoint = geometry == StyleGeometry.point;
    final isLine = geometry == StyleGeometry.line;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StyleSectionLabel(isLine ? 'Line Color' : 'Fill Color'),
        const SizedBox(height: 8),
        _ColorRow(
          color: isLine ? style.strokeColor : style.fillColor,
          onTap: () {
            final cur = isLine ? style.strokeColor : style.fillColor;
            _pickColor(
                context,
                cur,
                (c) => onChanged(isLine
                    ? style.copyWith(strokeColor: c)
                    : style.copyWith(fillColor: c, strokeColor: c)));
          },
        ),
        if (!isLine && !isPoint) ...[
          const SizedBox(height: 20),
          const StyleSectionLabel('Border Color'),
          const SizedBox(height: 8),
          _ColorRow(
            color: style.strokeColor,
            onTap: () => _pickColor(context, style.strokeColor,
                (c) => onChanged(style.copyWith(strokeColor: c))),
          ),
        ],
        const SizedBox(height: 20),
        StyleSectionLabel(isLine ? 'Opacity' : 'Fill Opacity'),
        const SizedBox(height: 4),
        _SliderRow(
          value: style.fillOpacity,
          min: featureMinOpacity,
          max: featureMaxOpacity,
          divisions: 19,
          label: '${(style.fillOpacity * 100).round()}%',
          onChanged: (v) => onChanged(style.copyWith(fillOpacity: v)),
        ),
        if (!isPoint) ...[
          const SizedBox(height: 12),
          const StyleSectionLabel('Line Width'),
          const SizedBox(height: 4),
          _SliderRow(
            value: style.strokeWidth,
            min: featureMinStrokeWidth,
            max: featureMaxStrokeWidth,
            divisions: 19,
            label: style.strokeWidth.toStringAsFixed(1),
            onChanged: (v) => onChanged(style.copyWith(strokeWidth: v)),
          ),
        ],
        if (isPoint) ...[
          const SizedBox(height: 12),
          const StyleSectionLabel('Point Size'),
          const SizedBox(height: 4),
          _SliderRow(
            value: style.pointSize,
            min: featureMinPointSize,
            max: featureMaxPointSize,
            divisions: 16,
            label: style.pointSize.toStringAsFixed(0),
            onChanged: (v) => onChanged(style.copyWith(pointSize: v)),
          ),
        ],
        const SizedBox(height: 16),
        const StyleSectionLabel('Preview'),
        const SizedBox(height: 8),
        StylePreview(style: style, geometry: geometry),
      ],
    );
  }
}

class StyleSectionLabel extends StatelessWidget {
  final String label;
  const StyleSectionLabel(this.label, {super.key});
  @override
  Widget build(BuildContext context) => Text(label,
      style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.4));
}

class _ColorRow extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _ColorRow({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Container(
              width: 24, height: 24,
              decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.grey[400]!)),
            ),
            const SizedBox(width: 12),
            Text(
              '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 13),
            ),
            const Spacer(),
            Icon(Icons.colorize, size: 18, color: Colors.grey[600]),
          ]),
        ),
      );
}

class _SliderRow extends StatelessWidget {
  final double value, min, max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;
  const _SliderRow(
      {required this.value,
      required this.min,
      required this.max,
      required this.divisions,
      required this.label,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged)),
        SizedBox(
            width: 48,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500),
                textAlign: TextAlign.end)),
      ]);
}

/// Pratinjau style untuk [geometry] (lingkaran / garis / kotak).
class StylePreview extends StatelessWidget {
  final LayerStyle style;
  final StyleGeometry geometry;
  const StylePreview({super.key, required this.style, required this.geometry});

  @override
  Widget build(BuildContext context) => Container(
        height: 70,
        decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!)),
        child: Center(
            child: CustomPaint(
                size: const Size(200, 50),
                painter: _PreviewPainter(style: style, geometry: geometry))),
      );
}

class _PreviewPainter extends CustomPainter {
  final LayerStyle style;
  final StyleGeometry geometry;
  const _PreviewPainter({required this.style, required this.geometry});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = style.fillColor.withValues(alpha: style.fillOpacity)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = style.strokeColor
      ..strokeWidth = style.strokeWidth.clamp(1.0, 4.0)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cx = size.width / 2;
    final cy = size.height / 2;

    if (geometry == StyleGeometry.point) {
      final r = style.pointSize.clamp(4.0, 18.0);
      canvas.drawCircle(Offset(cx, cy), r, fill);
      canvas.drawCircle(Offset(cx, cy), r, stroke);
    } else if (geometry == StyleGeometry.line) {
      canvas.drawPath(
          Path()
            ..moveTo(20, cy + 8)
            ..lineTo(cx - 20, cy - 8)
            ..lineTo(cx + 20, cy + 8)
            ..lineTo(size.width - 20, cy - 8),
          stroke);
    } else {
      final rr = RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(cx, cy),
              width: size.width - 40,
              height: size.height - 12),
          const Radius.circular(4));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter o) =>
      o.style != style || o.geometry != geometry;
}
