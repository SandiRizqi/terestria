import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:uuid/uuid.dart';

import '../../models/layer_model.dart';
import '../../services/layer_service.dart';
import '../../theme/app_theme.dart';

class LayersScreen extends StatefulWidget {
  const LayersScreen({Key? key}) : super(key: key);

  @override
  State<LayersScreen> createState() => _LayersScreenState();
}

class _LayersScreenState extends State<LayersScreen> {
  final LayerService _service = LayerService();
  final _uuid = const Uuid();

  List<LayerModel> _layers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final layers = await _service.loadLayers();
    if (mounted) {
      setState(() {
        _layers = layers;
        _isLoading = false;
      });
    }
  }

  // ────────────────────────────────────────────
  // Import GeoJSON
  // ────────────────────────────────────────────

  Future<void> _importLayer() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'geojson'],
    );
    if (result == null || result.files.single.path == null) return;

    final sourcePath = result.files.single.path!;
    final fileName = result.files.single.name;

    String content;
    try {
      content = await File(sourcePath).readAsString();
    } catch (e) {
      _showError('Cannot read file: $e');
      return;
    }

    Map<String, dynamic> geoJson;
    try {
      geoJson = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      _showError('Invalid GeoJSON: $e');
      return;
    }

    final geometryType = LayerService.detectGeometryType(geoJson);
    final propKeys = LayerService.detectPropertyKeys(geoJson);
    final defaultName = fileName.replaceAll(
        RegExp(r'\.(json|geojson)$', caseSensitive: false), '');

    final layerId = _uuid.v4();
    final newLayer = LayerModel(
      id: layerId,
      name: defaultName,
      filePath: sourcePath, // temp; replaced after import
      geometryType: geometryType,
      style: _defaultStyleForType(geometryType),
      isActive: true,
      createdAt: DateTime.now(),
    );

    if (!mounted) return;
    final edited = await _showStyleEditor(
        layer: newLayer, propKeys: propKeys, isNew: true);
    if (edited == null) return;

    try {
      final storedPath =
          await _service.importGeoJsonFile(sourcePath, edited.id);
      final saved = edited.copyWith(filePath: storedPath);
      await _service.saveLayer(saved);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text('Layer "${saved.name}" added'),
          ]),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      _showError('Error saving layer: $e');
    }
  }

  // ────────────────────────────────────────────
  // Edit / Delete / Toggle
  // ────────────────────────────────────────────

  Future<void> _editLayer(LayerModel layer) async {
    final geoJson = await _service.readGeoJson(layer.filePath);
    final propKeys = geoJson != null
        ? LayerService.detectPropertyKeys(geoJson)
        : <String>[];

    if (!mounted) return;
    final edited = await _showStyleEditor(
        layer: layer, propKeys: propKeys, isNew: false);
    if (edited == null) return;
    await _service.saveLayer(edited);
    _load();
  }

  Future<void> _deleteLayer(LayerModel layer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Layer'),
        content: Text('Delete "${layer.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _service.deleteLayer(layer.id);
    _load();
  }

  Future<void> _toggleLayer(LayerModel layer, bool value) async {
    await _service.toggleLayer(layer.id, value);
    _load();
  }

  Future<LayerModel?> _showStyleEditor({
    required LayerModel layer,
    required List<String> propKeys,
    required bool isNew,
  }) =>
      showModalBottomSheet<LayerModel>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _StyleEditorSheet(
            layer: layer, propKeys: propKeys, isNew: isNew),
      );

  // ────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────

  LayerStyle _defaultStyleForType(String type) {
    switch (type) {
      case 'Point':
        return LayerStyle(
            fillColor: Colors.red.shade400,
            fillOpacity: 0.9,
            strokeColor: Colors.red.shade700,
            strokeWidth: 2,
            pointSize: 8);
      case 'LineString':
        return LayerStyle(
            fillColor: Colors.blue.shade400,
            fillOpacity: 0.9,
            strokeColor: Colors.blue.shade600,
            strokeWidth: 3,
            pointSize: 6);
      default:
        return LayerStyle(
            fillColor: Colors.green.shade400,
            fillOpacity: 0.3,
            strokeColor: Colors.green.shade700,
            strokeWidth: 2,
            pointSize: 6);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error, color: Colors.white),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
      backgroundColor: Colors.red,
    ));
  }

  // ────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Layers'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh',
              onPressed: _load),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _layers.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _layers.length,
                  itemBuilder: (_, i) => _buildLayerCard(_layers[i]),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _importLayer,
        child: const Icon(Icons.add),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildEmptyState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.layers_outlined, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('No Layers Yet',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 8),
            Text('Import a GeoJSON file to add a layer',
                style: TextStyle(color: Colors.grey[500])),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _importLayer,
              icon: const Icon(Icons.upload_file),
              label: const Text('Import GeoJSON'),
            ),
          ],
        ),
      );

  Widget _buildLayerCard(LayerModel layer) {
    final color = layer.style.fillColor;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Geometry icon with color
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.5), width: 2),
              ),
              child: Icon(layer.geometryIcon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(layer.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(children: [
                    _TypeBadge(type: layer.geometryType, color: color),
                    if (layer.labelField != null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.label_outline,
                          size: 12, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(layer.labelField!,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[500]),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
            // Toggle active
            Switch(
              value: layer.isActive,
              onChanged: (v) => _toggleLayer(layer, v),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            // Context menu
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (val) {
                if (val == 'edit') _editLayer(layer);
                if (val == 'delete') _deleteLayer(layer);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Edit Style'),
                    ])),
                const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline,
                          size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete',
                          style: TextStyle(color: Colors.red)),
                    ])),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════
// Style Editor Bottom Sheet
// ═══════════════════════════════════════════════

class _StyleEditorSheet extends StatefulWidget {
  final LayerModel layer;
  final List<String> propKeys;
  final bool isNew;
  const _StyleEditorSheet(
      {required this.layer,
      required this.propKeys,
      required this.isNew});

  @override
  State<_StyleEditorSheet> createState() => _StyleEditorSheetState();
}

class _StyleEditorSheetState extends State<_StyleEditorSheet> {
  late TextEditingController _nameCtrl;
  late LayerStyle _style;
  String? _labelField;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.layer.name);
    _style = widget.layer.style;
    _labelField = widget.layer.labelField;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _pickColor(Color current, ValueChanged<Color> onChanged) {
    Color temp = current;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              onChanged(temp);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPoint = widget.layer.geometryType == 'Point';
    final isLine = widget.layer.geometryType == 'LineString';

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      maxChildSize: 0.94,
      minChildSize: 0.45,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
              child: Row(children: [
                Icon(widget.layer.geometryIcon,
                    color: AppTheme.primaryColor, size: 22),
                const SizedBox(width: 10),
                Text(widget.isNew ? 'New Layer' : 'Edit Layer',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  // Name
                  _SectionLabel('Layer Name'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                        hintText: 'Enter layer name', isDense: true),
                  ),

                  const SizedBox(height: 20),
                  _SectionLabel('Geometry Type'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Icon(widget.layer.geometryIcon,
                          size: 18, color: Colors.grey[700]),
                      const SizedBox(width: 8),
                      Text(widget.layer.geometryType,
                          style: TextStyle(color: Colors.grey[700])),
                    ]),
                  ),

                  const SizedBox(height: 20),
                  _SectionLabel(isLine ? 'Line Color' : 'Fill Color'),
                  const SizedBox(height: 8),
                  _ColorRow(
                    color: isLine ? _style.strokeColor : _style.fillColor,
                    onTap: () {
                      final cur = isLine
                          ? _style.strokeColor
                          : _style.fillColor;
                      _pickColor(cur, (c) {
                        setState(() {
                          _style = isLine
                              ? _style.copyWith(strokeColor: c)
                              : _style.copyWith(
                                  fillColor: c, strokeColor: c);
                        });
                      });
                    },
                  ),

                  if (!isLine && !isPoint) ...[
                    const SizedBox(height: 20),
                    _SectionLabel('Border Color'),
                    const SizedBox(height: 8),
                    _ColorRow(
                      color: _style.strokeColor,
                      onTap: () => _pickColor(
                          _style.strokeColor,
                          (c) => setState(
                              () => _style =
                                  _style.copyWith(strokeColor: c))),
                    ),
                  ],

                  const SizedBox(height: 20),
                  _SectionLabel(
                      isLine ? 'Opacity' : 'Fill Opacity'),
                  const SizedBox(height: 4),
                  _SliderRow(
                    value: _style.fillOpacity,
                    min: 0.05, max: 1.0, divisions: 19,
                    label:
                        '${(_style.fillOpacity * 100).round()}%',
                    onChanged: (v) => setState(() =>
                        _style = _style.copyWith(fillOpacity: v)),
                  ),

                  if (!isPoint) ...[
                    const SizedBox(height: 12),
                    _SectionLabel('Line Width'),
                    const SizedBox(height: 4),
                    _SliderRow(
                      value: _style.strokeWidth,
                      min: 0.5, max: 10.0, divisions: 19,
                      label: _style.strokeWidth.toStringAsFixed(1),
                      onChanged: (v) => setState(() =>
                          _style = _style.copyWith(strokeWidth: v)),
                    ),
                  ],

                  if (isPoint) ...[
                    const SizedBox(height: 12),
                    _SectionLabel('Point Size'),
                    const SizedBox(height: 4),
                    _SliderRow(
                      value: _style.pointSize,
                      min: 4.0, max: 20.0, divisions: 16,
                      label: _style.pointSize.toStringAsFixed(0),
                      onChanged: (v) => setState(() =>
                          _style = _style.copyWith(pointSize: v)),
                    ),
                  ],

                  const SizedBox(height: 16),
                  _SectionLabel('Preview'),
                  const SizedBox(height: 8),
                  _StylePreview(
                      style: _style,
                      geometryType: widget.layer.geometryType),

                  if (widget.propKeys.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionLabel('Label Field'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String?>(
                      value: _labelField,
                      decoration: const InputDecoration(
                          hintText: 'None (no labels)',
                          isDense: true),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('None')),
                        ...widget.propKeys.map((k) =>
                            DropdownMenuItem<String?>(
                                value: k, child: Text(k))),
                      ],
                      onChanged: (v) =>
                          setState(() => _labelField = v),
                    ),
                  ],

                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      final name = _nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      Navigator.pop(
                          context,
                          widget.layer.copyWith(
                            name: name,
                            style: _style,
                            labelField: _labelField,
                            clearLabelField: _labelField == null,
                          ));
                    },
                    style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(
                        widget.isNew ? 'Add Layer' : 'Save Changes',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Reusable sub-widgets
// ─────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
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
              '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
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

class _StylePreview extends StatelessWidget {
  final LayerStyle style;
  final String geometryType;
  const _StylePreview(
      {required this.style, required this.geometryType});

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
                painter: _PreviewPainter(
                    style: style, type: geometryType))),
      );
}

class _PreviewPainter extends CustomPainter {
  final LayerStyle style;
  final String type;
  const _PreviewPainter({required this.style, required this.type});

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = style.fillColor.withOpacity(style.fillOpacity)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = style.strokeColor
      ..strokeWidth = style.strokeWidth.clamp(1.0, 4.0)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cx = size.width / 2;
    final cy = size.height / 2;

    if (type == 'Point') {
      final r = style.pointSize.clamp(4.0, 18.0);
      canvas.drawCircle(Offset(cx, cy), r, fill);
      canvas.drawCircle(Offset(cx, cy), r, stroke);
    } else if (type == 'LineString') {
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
      o.style != style || o.type != type;
}

class _TypeBadge extends StatelessWidget {
  final String type;
  final Color color;
  const _TypeBadge({required this.type, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4)),
        child: Text(type.toUpperCase(),
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600)),
      );
}
