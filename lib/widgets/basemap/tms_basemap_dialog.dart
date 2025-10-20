import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/basemap_model.dart';
import '../../theme/app_theme.dart';

class TmsBasemapDialog extends StatefulWidget {
  final Basemap? basemap;

  const TmsBasemapDialog({Key? key, this.basemap}) : super(key: key);

  @override
  State<TmsBasemapDialog> createState() => _TmsBasemapDialogState();
}

class _TmsBasemapDialogState extends State<TmsBasemapDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _attributionController = TextEditingController();
  final _uuid = const Uuid();

  int _minZoom = 0;
  int _maxZoom = 18;

  @override
  void initState() {
    super.initState();
    if (widget.basemap != null) {
      _nameController.text = widget.basemap!.name;
      _urlController.text = widget.basemap!.urlTemplate;
      _attributionController.text = widget.basemap!.attribution ?? '';
      _minZoom = widget.basemap!.minZoom;
      _maxZoom = widget.basemap!.maxZoom;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _attributionController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final basemap = Basemap(
      id: widget.basemap?.id ?? _uuid.v4(),
      name: _nameController.text.trim(),
      type: BasemapType.custom,
      urlTemplate: _urlController.text.trim(),
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      attribution: _attributionController.text.trim().isEmpty
          ? null
          : _attributionController.text.trim(),
    );

    Navigator.pop(context, basemap);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.basemap == null ? 'Add TMS Basemap' : 'Edit Basemap'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Basemap Name',
                  hintText: 'e.g., My Custom Map',
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'TMS URL Template',
                  hintText: 'https://example.com/{z}/{x}/{y}.png',
                  prefixIcon: Icon(Icons.link),
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter URL template';
                  }
                  if (!value.contains('{z}') || 
                      !value.contains('{x}') || 
                      !value.contains('{y}')) {
                    return 'URL must contain {z}, {x}, and {y}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              
              TextFormField(
                controller: _attributionController,
                decoration: const InputDecoration(
                  labelText: 'Attribution (Optional)',
                  hintText: '© Map Provider',
                  prefixIcon: Icon(Icons.copyright),
                ),
              ),
              const SizedBox(height: AppTheme.spacingLarge),
              
              _buildZoomControls(),
              
              const SizedBox(height: AppTheme.spacingMedium),
              _buildInfoBox(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Zoom Levels',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Min: $_minZoom', 
                    style: const TextStyle(fontSize: 12)),
                  Slider(
                    value: _minZoom.toDouble(),
                    min: 0,
                    max: 20,
                    divisions: 20,
                    label: _minZoom.toString(),
                    onChanged: (value) {
                      setState(() {
                        _minZoom = value.toInt();
                        if (_minZoom > _maxZoom) _maxZoom = _minZoom;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Max: $_maxZoom', 
                    style: const TextStyle(fontSize: 12)),
                  Slider(
                    value: _maxZoom.toDouble(),
                    min: 0,
                    max: 20,
                    divisions: 20,
                    label: _maxZoom.toString(),
                    onChanged: (value) {
                      setState(() {
                        _maxZoom = value.toInt();
                        if (_maxZoom < _minZoom) _minZoom = _maxZoom;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.lightGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.lightGreen),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, 
                size: 16, color: AppTheme.darkGreen),
              const SizedBox(width: 8),
              Text(
                'TMS URL Format',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.darkGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Use {z} for zoom, {x} for X coordinate, {y} for Y coordinate.\n'
            'Example: https://tile.server.com/{z}/{x}/{y}.png\n\n'
            'Tiles will be cached automatically for offline use.',
            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
