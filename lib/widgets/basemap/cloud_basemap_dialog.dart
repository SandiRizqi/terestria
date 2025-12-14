import 'package:flutter/material.dart';
import '../../models/cloud_basemap_model.dart';
import '../../models/basemap_model.dart';
import '../../services/cloud_basemap_service.dart';
import '../../services/basemap_service.dart';
import '../../theme/app_theme.dart';
import 'package:uuid/uuid.dart';

/// Dialog untuk menampilkan daftar basemap dari cloud dan memilih mana yang akan ditambahkan
class CloudBasemapDialog extends StatefulWidget {
  const CloudBasemapDialog({Key? key}) : super(key: key);

  @override
  State<CloudBasemapDialog> createState() => _CloudBasemapDialogState();
}

class _CloudBasemapDialogState extends State<CloudBasemapDialog> {
  final CloudBasemapService _cloudService = CloudBasemapService();
  final BasemapService _basemapService = BasemapService();
  final _uuid = const Uuid();
  final _searchController = TextEditingController();
  
  bool _isLoading = true;
  String? _errorMessage;
  List<CloudBasemap> _cloudBasemaps = [];
  List<CloudBasemap> _filteredBasemaps = [];
  Set<int> _selectedIds = {};
  List<Basemap> _existingBasemaps = [];

  @override
  void initState() {
    super.initState();
    _loadCloudBasemaps();
    _searchController.addListener(_filterBasemaps);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterBasemaps() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredBasemaps = _cloudBasemaps;
      } else {
        _filteredBasemaps = _cloudBasemaps.where((basemap) {
          return basemap.name.toLowerCase().contains(query) ||
                 basemap.company.name.toLowerCase().contains(query) ||
                 basemap.company.group.toLowerCase().contains(query) ||
                 basemap.description.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadCloudBasemaps() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load existing basemaps untuk check duplikasi
      _existingBasemaps = await _basemapService.getBasemaps();
      
      // Fetch dari cloud
      final response = await _cloudService.fetchCloudBasemaps();
      
      if (response != null && response.success) {
        setState(() {
          _cloudBasemaps = response.data;
          _filteredBasemaps = response.data;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response?.message ?? 'Failed to load basemaps from cloud';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  bool _isAlreadyAdded(CloudBasemap cloudBasemap) {
    // Check berdasarkan proxyUrl karena itu yang unique
    return _existingBasemaps.any((b) => b.urlTemplate == cloudBasemap.proxyUrl);
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _addSelectedBasemaps() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one basemap')),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Adding basemaps...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      int addedCount = 0;
      
      for (final id in _selectedIds) {
        final cloudBasemap = _cloudBasemaps.firstWhere((b) => b.id == id);
        
        // Skip jika sudah ada
        if (_isAlreadyAdded(cloudBasemap)) {
          continue;
        }
        
        // Convert CloudBasemap ke Basemap
        final basemap = Basemap(
          id: _uuid.v4(),
          name: cloudBasemap.name,
          type: BasemapType.custom, // TMS basemap menggunakan type custom
          urlTemplate: cloudBasemap.proxyUrl, // Gunakan proxyUrl
          minZoom: cloudBasemap.minZoom,
          maxZoom: cloudBasemap.maxZoom,
          createdAt: DateTime.now(),
        );
        
        await _basemapService.saveBasemap(basemap);
        addedCount++;
      }

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
        
        // Close this dialog dan return success
        Navigator.pop(context, addedCount);
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding basemaps: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 650),
        child: Column(
          children: [
            // Header
            Container(
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                  
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.cloud_download, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Add Basemap from Cloud',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            
            // Search bar
            if (!_isLoading && _cloudBasemaps.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search basemaps...',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.primaryColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            
            // Content
            Expanded(
              child: _buildContent(),
            ),
            
            // Actions
            if (!_isLoading && _cloudBasemaps.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(
                    top: BorderSide(color: Colors.grey[200]!),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_selectedIds.length} selected',
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _selectedIds.isEmpty ? null : _addSelectedBasemaps,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text(
                            'Add Selected',
                            style: TextStyle(fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading basemaps from cloud...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadCloudBasemaps,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_cloudBasemaps.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No basemaps available',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredBasemaps.isEmpty && _searchController.text.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No basemaps found for "${_searchController.text}"',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _filteredBasemaps.length,
      itemBuilder: (context, index) {
        final basemap = _filteredBasemaps[index];
        final isSelected = _selectedIds.contains(basemap.id);
        final isAlreadyAdded = _isAlreadyAdded(basemap);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: isSelected ? 3 : 1,
          child: InkWell(
            onTap: isAlreadyAdded ? null : () => _toggleSelection(basemap.id),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Checkbox
                  Transform.scale(
                    scale: 0.85,
                    child: Checkbox(
                      value: isAlreadyAdded ? true : isSelected,
                      onChanged: isAlreadyAdded ? null : (value) {
                        _toggleSelection(basemap.id);
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  
                  const SizedBox(width: 8),
                  
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: isAlreadyAdded 
                          ? Colors.grey[300]
                          : AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      Icons.map,
                      size: 16,
                      color: isAlreadyAdded 
                          ? Colors.grey[600]
                          : AppTheme.primaryColor,
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                basemap.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isAlreadyAdded 
                                      ? Colors.grey[600]
                                      : Colors.black87,
                                ),
                              ),
                            ),
                            if (isAlreadyAdded)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green[100],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'Added',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${basemap.company.name} • ${basemap.company.group}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (basemap.description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            basemap.description,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 2),
                        Text(
                          'Zoom: ${basemap.minZoom}-${basemap.maxZoom}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
