import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/basemap_model.dart';
import '../../services/basemap_service.dart';
import '../../theme/app_theme.dart';

class BasemapScreen extends StatefulWidget {
  const BasemapScreen({Key? key}) : super(key: key);

  @override
  State<BasemapScreen> createState() => _BasemapScreenState();
}

class _BasemapScreenState extends State<BasemapScreen> {
  final BasemapService _basemapService = BasemapService();
  final _uuid = const Uuid();
  
  List<Basemap> _basemaps = [];
  Basemap? _selectedBasemap;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBasemaps();
  }

  Future<void> _loadBasemaps() async {
    setState(() => _isLoading = true);
    
    try {
      final basemaps = await _basemapService.getBasemaps();
      final selected = await _basemapService.getSelectedBasemap();
      
      setState(() {
        _basemaps = basemaps;
        _selectedBasemap = selected;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading basemaps: $e')),
        );
      }
    }
  }

  Future<void> _selectBasemap(Basemap basemap) async {
    await _basemapService.setSelectedBasemap(basemap.id);
    setState(() => _selectedBasemap = basemap);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${basemap.name} selected')),
      );
    }
  }

  Future<void> _addCustomBasemap() async {
    final result = await showDialog<Basemap>(
      context: context,
      builder: (context) => const AddBasemapDialog(),
    );

    if (result != null) {
      await _basemapService.saveBasemap(result);
      _loadBasemaps();
    }
  }

  Future<void> _editBasemap(Basemap basemap) async {
    final result = await showDialog<Basemap>(
      context: context,
      builder: (context) => AddBasemapDialog(basemap: basemap),
    );

    if (result != null) {
      await _basemapService.saveBasemap(result);
      _loadBasemaps();
    }
  }

  Future<void> _deleteBasemap(Basemap basemap) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Basemap'),
        content: Text('Are you sure you want to delete "${basemap.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _basemapService.deleteBasemap(basemap.id);
      
      // If deleted basemap was selected, select default
      if (_selectedBasemap?.id == basemap.id) {
        final defaultBasemap = _basemaps.firstWhere((b) => b.isDefault);
        await _selectBasemap(defaultBasemap);
      }
      
      _loadBasemaps();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Basemaps'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              children: [
                // Built-in basemaps
                Text(
                  'Built-in Basemaps',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppTheme.spacingMedium),
                ..._basemaps
                    .where((b) => b.type == BasemapType.builtin)
                    .map((basemap) => _buildBasemapCard(basemap)),
                
                const SizedBox(height: AppTheme.spacingLarge),
                
                // Custom basemaps
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Custom Basemaps',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      onPressed: _addCustomBasemap,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMedium),
                
                if (_basemaps.where((b) => b.type == BasemapType.custom).isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppTheme.spacingLarge),
                      child: Column(
                        children: [
                          Icon(
                            Icons.map,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: AppTheme.spacingMedium),
                          Text(
                            'No custom basemaps yet',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: AppTheme.spacingSmall),
                          Text(
                            'Tap the + icon to add a custom TMS basemap',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ..._basemaps
                      .where((b) => b.type == BasemapType.custom)
                      .map((basemap) => _buildBasemapCard(basemap)),
                
                const SizedBox(height: AppTheme.spacingLarge),
                
                // Info card
                Card(
                  color: Colors.blue[50],
                  child: Padding(
                    padding: const EdgeInsets.all(AppTheme.spacingMedium),
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue[700]),
                        const SizedBox(width: AppTheme.spacingMedium),
                        Expanded(
                          child: Text(
                            'Tiles are cached offline automatically when you zoom in. Clear cache from Settings if needed.',
                            style: TextStyle(
                              color: Colors.blue[900],
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBasemapCard(Basemap basemap) {
    final isSelected = _selectedBasemap?.id == basemap.id;
    
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      elevation: isSelected ? AppTheme.elevationMedium : AppTheme.elevationLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        side: isSelected
            ? BorderSide(color: AppTheme.primaryColor, width: 2)
            : BorderSide.none,
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[300],
            borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
          ),
          child: Icon(
            Icons.map,
            color: isSelected ? Colors.white : Colors.grey[600],
          ),
        ),
        title: Text(
          basemap.name,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              basemap.type == BasemapType.builtin ? 'Built-in' : 'Custom TMS',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            if (basemap.attribution != null)
              Text(
                basemap.attribution!,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: AppTheme.primaryColor,
              ),
            if (basemap.type == BasemapType.custom) ...[
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _editBasemap(basemap),
                color: Colors.blue,
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20),
                onPressed: () => _deleteBasemap(basemap),
                color: AppTheme.errorColor,
              ),
            ],
          ],
        ),
        onTap: () => _selectBasemap(basemap),
      ),
    );
  }
}

class AddBasemapDialog extends StatefulWidget {
  final Basemap? basemap;

  const AddBasemapDialog({Key? key, this.basemap}) : super(key: key);

  @override
  State<AddBasemapDialog> createState() => _AddBasemapDialogState();
}

class _AddBasemapDialogState extends State<AddBasemapDialog> {
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
      name: _nameController.text,
      type: BasemapType.custom,
      urlTemplate: _urlController.text,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      attribution: _attributionController.text.isEmpty ? null : _attributionController.text,
    );

    Navigator.pop(context, basemap);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.basemap == null ? 'Add Custom Basemap' : 'Edit Basemap'),
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
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
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
                ),
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a URL template';
                  }
                  if (!value.contains('{z}') || !value.contains('{x}') || !value.contains('{y}')) {
                    return 'URL must contain {z}, {x}, and {y} placeholders';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              
              TextFormField(
                controller: _attributionController,
                decoration: const InputDecoration(
                  labelText: 'Attribution (optional)',
                  hintText: '© Map Provider',
                ),
              ),
              const SizedBox(height: AppTheme.spacingLarge),
              
              Text(
                'Zoom Levels',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Min Zoom: $_minZoom'),
                        Slider(
                          value: _minZoom.toDouble(),
                          min: 0,
                          max: 20,
                          divisions: 20,
                          label: _minZoom.toString(),
                          onChanged: (value) {
                            setState(() {
                              _minZoom = value.toInt();
                              if (_minZoom > _maxZoom) {
                                _maxZoom = _minZoom;
                              }
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
                        Text('Max Zoom: $_maxZoom'),
                        Slider(
                          value: _maxZoom.toDouble(),
                          min: 0,
                          max: 20,
                          divisions: 20,
                          label: _maxZoom.toString(),
                          onChanged: (value) {
                            setState(() {
                              _maxZoom = value.toInt();
                              if (_maxZoom < _minZoom) {
                                _minZoom = _maxZoom;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: AppTheme.spacingMedium),
              
              Container(
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                    const SizedBox(width: AppTheme.spacingSmall),
                    Expanded(
                      child: Text(
                        'Use TMS format with {z}/{x}/{y} placeholders. Tiles will be cached offline automatically.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[900],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
}
