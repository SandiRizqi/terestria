import 'package:flutter/material.dart';
import '../../models/cloud_project_model.dart';
import '../../models/project_model.dart';
import '../../models/form_field_model.dart' as field_model;
import '../../services/cloud_project_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

/// Dialog untuk menampilkan daftar projects dari cloud dan memilih mana yang akan ditambahkan
class CloudProjectDialog extends StatefulWidget {
  const CloudProjectDialog({Key? key}) : super(key: key);

  @override
  State<CloudProjectDialog> createState() => _CloudProjectDialogState();
}

class _CloudProjectDialogState extends State<CloudProjectDialog> {
  final CloudProjectService _cloudService = CloudProjectService();
  final StorageService _storageService = StorageService();
  final _searchController = TextEditingController();
  
  bool _isLoading = true;
  String? _errorMessage;
  List<CloudProject> _cloudProjects = [];
  List<CloudProject> _filteredProjects = [];
  Set<String> _selectedIds = {};
  List<Project> _existingProjects = [];

  @override
  void initState() {
    super.initState();
    _loadCloudProjects();
    _searchController.addListener(_filterProjects);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterProjects() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredProjects = _cloudProjects;
      } else {
        _filteredProjects = _cloudProjects.where((project) {
          return project.name.toLowerCase().contains(query) ||
                 project.description.toLowerCase().contains(query) ||
                 project.createdBy.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadCloudProjects() async {
    print('🚀 CloudProjectDialog: Starting to load projects...');
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Load existing projects untuk check duplikasi
      _existingProjects = await _storageService.loadProjects();
      print('📂 Loaded ${_existingProjects.length} existing projects');
      
      // Fetch dari cloud menggunakan endpoint yang sama dengan sync
      print('☁️ Fetching from cloud...');
      final response = await _cloudService.fetchCloudProjects();
      
      print('📬 Response received: ${response != null ? 'success=${response.success}' : 'null'}');
      
      if (response != null && response.success) {
        print('✅ Success! Got ${response.data.length} cloud projects');
        
        if (response.data.isEmpty) {
          print('⚠️ No projects available from cloud');
          setState(() {
            _cloudProjects = [];
            _filteredProjects = [];
            _isLoading = false;
          });
        } else {
          print('📋 Projects:');
          for (var project in response.data) {
            print('   - ${project.name} (${project.geometryType})');
          }
          
          setState(() {
            _cloudProjects = response.data;
            _filteredProjects = response.data;
            _isLoading = false;
          });
        }
      } else {
        final errorMsg = response?.message ?? 'Failed to load projects from cloud';
        print('❌ Error: $errorMsg');
        
        setState(() {
          _errorMessage = errorMsg;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      print('❌ Exception loading cloud projects: $e');
      print('Stack trace: $stackTrace');
      
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  bool _isAlreadyAdded(CloudProject cloudProject) {
    // Check berdasarkan ID project
    return _existingProjects.any((p) => p.id == cloudProject.id);
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _addSelectedProjects() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one project')),
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
                Text('Adding projects...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      int addedCount = 0;
      
      for (final id in _selectedIds) {
        final cloudProject = _cloudProjects.firstWhere((p) => p.id == id);
        
        // Skip jika sudah ada
        if (_isAlreadyAdded(cloudProject)) {
          continue;
        }
        
        // Convert CloudProject ke Project
        final project = Project(
          id: cloudProject.id,
          name: cloudProject.name,
          description: cloudProject.description,
          geometryType: _parseGeometryType(cloudProject.geometryType),
          formFields: _convertFormFields(cloudProject.formFields),
          createdAt: cloudProject.createdAt,
          updatedAt: cloudProject.updatedAt,
          createdBy: cloudProject.createdBy,
        );
        
        await _storageService.saveProject(project);
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
          SnackBar(content: Text('Error adding projects: $e')),
        );
      }
    }
  }

  GeometryType _parseGeometryType(String type) {
    switch (type.toLowerCase()) {
      case 'point':
        return GeometryType.point;
      case 'line':
        return GeometryType.line;
      case 'polygon':
        return GeometryType.polygon;
      default:
        return GeometryType.point;
    }
  }

  List<field_model.FormFieldModel> _convertFormFields(List<FormFieldData> cloudFields) {
    return cloudFields.map((field) {
      return field_model.FormFieldModel(
        id: field.label.toLowerCase().replaceAll(' ', '_'),
        label: field.label,
        type: _parseFieldType(field.type),
        required: field.required,
        options: field.options,
      );
    }).toList();
  }

  field_model.FieldType _parseFieldType(String type) {
    switch (type.toLowerCase()) {
      case 'text':
        return field_model.FieldType.text;
      case 'number':
        return field_model.FieldType.number;
      case 'date':
        return field_model.FieldType.date;
      case 'dropdown':
        return field_model.FieldType.dropdown;
      case 'checkbox':
        return field_model.FieldType.checkbox;
      case 'photo':
        return field_model.FieldType.photo;
      default:
        return field_model.FieldType.text;
    }
  }

  IconData _getGeometryIconData(String type) {
    switch (type.toLowerCase()) {
      case 'point':
        return Icons.place;
      case 'line':
        return Icons.timeline;
      case 'polygon':
        return Icons.crop_square;
      default:
        return Icons.place;
    }
  }

  Color _getGeometryColor(String type) {
    switch (type.toLowerCase()) {
      case 'point':
        return AppTheme.pointColor; // Red
      case 'line':
        return AppTheme.lineColor; // Blue
      case 'polygon':
        return AppTheme.polygonColor; // Green
      default:
        return AppTheme.pointColor;
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
                      'Add Project from Cloud',
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
            if (!_isLoading && _cloudProjects.isNotEmpty)
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
                    hintText: 'Search projects...',
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
            if (!_isLoading && _cloudProjects.isNotEmpty)
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
                          onPressed: _selectedIds.isEmpty ? null : _addSelectedProjects,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text(
                            'Add Selected',
                            style: TextStyle(fontSize: 13),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
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
            Text('Loading projects from cloud...'),
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
                onPressed: _loadCloudProjects,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_cloudProjects.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No projects available',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredProjects.isEmpty && _searchController.text.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No projects found for "${_searchController.text}"',
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
      itemCount: _filteredProjects.length,
      itemBuilder: (context, index) {
        final project = _filteredProjects[index];
        final isSelected = _selectedIds.contains(project.id);
        final isAlreadyAdded = _isAlreadyAdded(project);
        final geometryColor = _getGeometryColor(project.geometryType);
        final geometryIcon = _getGeometryIconData(project.geometryType);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: isSelected ? 3 : 1,
          child: InkWell(
            onTap: isAlreadyAdded ? null : () => _toggleSelection(project.id),
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
                        _toggleSelection(project.id);
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  
                  const SizedBox(width: 8),
                  
                  // Geometry Icon - Same style as ProjectCard
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isAlreadyAdded 
                          ? Colors.grey[300]
                          : geometryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      geometryIcon,
                      color: isAlreadyAdded ? Colors.grey[600] : geometryColor,
                      size: 24,
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
                                project.name,
                                style: TextStyle(
                                  fontSize: 14,
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
                        const SizedBox(height: 4),
                        // Geometry type chip - same style as ProjectCard
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: geometryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                project.geometryType.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: geometryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.person_outline, 
                              size: 11, 
                              color: Colors.grey[500]
                            ),
                            const SizedBox(width: 4),
                            Text(
                              project.createdBy,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        if (project.description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            project.description,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.edit_note, size: 11, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '${project.formFields.length} fields',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.cloud, size: 11, color: Colors.grey[500]),
                            const SizedBox(width: 4),
                            Text(
                              '${project.dataCount} data',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
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
          ),
        );
      },
    );
  }
}
