import 'package:flutter/material.dart';
import '../../models/project_model.dart';
import '../../services/storage_service.dart';
import '../../services/auth_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/sync_service.dart';
import '../../services/api_service.dart';
import '../../config/api_config.dart';
import '../auth/login_screen.dart';
import '../project/create_project_screen.dart';
import '../project/project_detail_screen.dart';
import '../../widgets/project_card.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';
import '../../services/project_template_service.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:async';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({Key? key}) : super(key: key);

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final StorageService _storageService = StorageService();
  final AuthService _authService = AuthService();
  final ConnectivityService _connectivityService = ConnectivityService();
  final SyncService _syncService = SyncService();
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  
  List<Project> _projects = [];
  List<Project> _filteredProjects = [];
  bool _isLoading = true;
  bool _isSearching = false;
  bool _isOnline = false;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _initConnectivity();
  }

  void _initConnectivity() {
    _connectivityService.startMonitoring();
    _isOnline = _connectivityService.isOnline;
    _connectivitySubscription = _connectivityService.connectivityStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    setState(() => _isLoading = true);
    try {
      final projects = await _storageService.loadProjects();
      setState(() {
        _projects = projects;
        _filteredProjects = projects;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading projects: $e')),
        );
      }
    }
  }

  void _filterProjects(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProjects = _projects;
      } else {
        _filteredProjects = _projects.where((project) {
          final nameLower = project.name.toLowerCase();
          final descLower = project.description.toLowerCase();
          final createdLower = project.createdBy?.toLowerCase();
          final searchLower = query.toLowerCase();
          return nameLower.contains(searchLower) || descLower.contains(searchLower) || createdLower != null && createdLower.contains(searchLower);
        }).toList();
      }
    });
  }

  /// Sync projects dari server (Pull dari server ke local)
  Future<void> _syncProjectsFromServer() async {
    if (_isSyncing) return;

    // Check if online
    if (!_isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.wifi_off, color: Colors.white),
                SizedBox(width: 8),
                Text('No internet connection. Please connect to sync.'),
              ],
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final projectResponse = await _apiService.get(
        '${ApiConfig.syncProjectEndpoint}?user_only=true',
      );

      if (_apiService.isSuccess(projectResponse)) {
        final projectData = jsonDecode(projectResponse.body);
        int newProjectCount = 0;
        int updatedProjectCount = 0;

        // Load existing projects
        final existingProjects = await _storageService.loadProjects();
        final existingProjectMap = {for (var p in existingProjects) p.id: p};

        // Buat set ID dari projects di server
        Set<String> serverProjectIds = {};
        int deletedProjectCount = 0;

        // Process projects dari server
        if (projectData is List) {
          for (var projectJson in projectData) {
            try {
              final serverProject = Project.fromJson(projectJson);
              serverProjectIds.add(serverProject.id);
              final existingProject = existingProjectMap[serverProject.id];

              if (existingProject == null) {
                // Project baru dari server
                await _storageService.saveProject(serverProject);
                newProjectCount++;
              } else if (serverProject.updatedAt.isAfter(existingProject.updatedAt)) {
                // Update project yang lebih baru dari server
                await _storageService.saveProject(serverProject);
                updatedProjectCount++;
              }
            } catch (e) {
              print('Error processing project from server: $e');
            }
          }

          // Hapus projects local yang tidak ada di server
          for (var existingProject in existingProjects) {
            if (!serverProjectIds.contains(existingProject.id)) {
              try {
                await _storageService.deleteProject(existingProject.id);
                deletedProjectCount++;
                print('Deleted local project not found on server: ${existingProject.name}');
              } catch (e) {
                print('Error deleting local project: $e');
              }
            }
          }
        }

        // Reload local data
        await _loadProjects();

        // Show notification
        if (mounted) {
          int totalChanges = newProjectCount + updatedProjectCount + deletedProjectCount;
          
          if (totalChanges > 0) {
            List<String> messageParts = [];
            if (newProjectCount > 0) {
              messageParts.add('$newProjectCount new');
            }
            if (updatedProjectCount > 0) {
              messageParts.add('$updatedProjectCount updated');
            }
            if (deletedProjectCount > 0) {
              messageParts.add('$deletedProjectCount deleted');
            }
            
            String message = messageParts.join(', ');
            message += ' project${totalChanges > 1 ? "s" : ""} synced from server';
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.cloud_download, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(child: Text(message)),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Projects are up to date'),
                  ],
                ),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      //print('Error syncing projects from server: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error syncing from server: $e')),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  /// Push projects ke server (Upload local ke server)
  Future<void> _syncProjectsToServer() async {
    // Check if online
    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.white),
              SizedBox(width: 8),
              Text('No internet connection. Please connect to sync.'),
            ],
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Projects'),
        content: Text('Upload ${_projects.length} project${_projects.length > 1 ? "s" : ""} to server?\n\nThis will upload project structures and form fields.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sync'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Show loading
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Syncing projects to server...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      int successCount = 0;
      List<String> errors = [];
      
      // Sync each project to backend
      for (var project in _projects) {
        final result = await _syncService.syncProject(project);
        
        if (result.success) {
          // Update project sync status
          final updatedProject = project.copyWith(
            updatedAt: DateTime.now(),
          );
          await _storageService.saveProject(updatedProject);
          successCount++;
        } else {
          errors.add('${project.name}: ${result.message}');
        }
      }

      // Reload projects
      await _loadProjects();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        if (successCount == _projects.length) {
          // All synced successfully
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$successCount project${successCount > 1 ? "s" : ""} synced successfully',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );
        } else if (successCount > 0) {
          // Partial success
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('Partial Sync'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$successCount of ${_projects.length} projects synced.'),
                    const SizedBox(height: 12),
                    const Text(
                      'Errors:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...errors.take(5).map((error) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $error',
                        style: const TextStyle(fontSize: 12),
                      ),
                    )),
                    if (errors.length > 5)
                      Text('... and ${errors.length - 5} more errors'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          // All failed
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.error, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Sync Failed'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Failed to sync projects to server.'),
                    const SizedBox(height: 12),
                    const Text(
                      'Errors:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...errors.take(5).map((error) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $error',
                        style: const TextStyle(fontSize: 12),
                      ),
                    )),
                    if (errors.length > 5)
                      Text('... and ${errors.length - 5} more errors'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error syncing projects: $e')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteProject(Project project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Project'),
        content: Text('Are you sure you want to delete "${project.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _storageService.deleteProject(project.id);
        _loadProjects();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Project deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting project: $e')),
          );
        }
      }
    }
  }

  Future<void> _editProject(Project project) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateProjectScreen(project: project),
      ),
    );

    // Reload projects jika ada perubahan
    if (result == true) {
      await _loadProjects();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching 
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search projects...',
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                ),
                onChanged: _filterProjects,
              )
            : const Text('Projects'),
        actions: [
          if (!_isSearching) ...[
            const ConnectivityIndicator(
              showLabel: true,
              iconSize: 16,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search Projects',
              onPressed: () {
                setState(() => _isSearching = true);
              },
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 8,
              offset: const Offset(0, 50),
              onSelected: (value) {
                if (value == 'pull_from_server') {
                  _syncProjectsFromServer();
                } else if (value == 'sync_to_server') {
                  _syncProjectsToServer();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'pull_from_server',
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.cloud_download_rounded,
                          color: Colors.green,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pull from Server',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Download projects from cloud',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sync_to_server',
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.cloud_upload_rounded,
                          color: Theme.of(context).primaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Push to Server',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Upload projects to cloud',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchController.clear();
                  _filteredProjects = _projects;
                });
              },
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Sync Indicator
          if (_isSyncing)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.blue[50],
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Syncing with server...',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          
          // Project List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProjects.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: () async {
                          // Saat pull to refresh, sync projects dari server
                          if (_isOnline) {
                            await _syncProjectsFromServer();
                          } else {
                            await _loadProjects();
                          }
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 0,
                            bottom: 80, // Padding untuk FAB
                          ),
                          itemCount: _filteredProjects.length,
                          itemBuilder: (context, index) {
                            final project = _filteredProjects[index];
                            return ProjectCard(
                              project: project,
                              onTap: () => _navigateToProjectDetail(project),
                              onDelete: () => _deleteProject(project),
                              onEdit: () => _editProject(project),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateProject,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 6,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltering = _searchController.text.isNotEmpty;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFiltering ? Icons.search_off : Icons.folder_open,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            isFiltering ? 'No Projects Found' : 'No Projects Yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            isFiltering 
                ? 'Try different search keywords'
                : 'Create your first project to start collecting geospatial data',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          if (!isFiltering)
            ElevatedButton.icon(
              onPressed: _navigateToCreateProject,
              icon: const Icon(Icons.add),
              label: const Text('Create Project'),
            ),
        ],
      ),
    );
  }

  void _navigateToCreateProject() async {
    // Show dialog to choose between new project or from template
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_circle_outline),
            SizedBox(width: 8),
            Text('Create Project'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('How would you like to create your project?'),
            const SizedBox(height: 24),
            // Create New button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, 'new'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text(
                  'Create New Project',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // From Template button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'template'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(
                    color: Theme.of(context).primaryColor,
                    width: 2,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.upload_file),
                label: const Text(
                  'Import from Template',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'new') {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const CreateProjectScreen(),
        ),
      );

      if (result == true) {
        _loadProjects();
      }
    } else if (choice == 'template') {
      _showTemplateImportOptions();
    }
  }

  void _showTemplateImportOptions() async {
    // Pick JSON file
    try {
      // For now, we'll use file picker
      // You need to add file_picker package to pubspec.yaml
      // For simplicity, I'll show dialog to enter file path or use a simple approach
      
      final result = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.upload_file),
              SizedBox(width: 8),
              Text('Import Template'),
            ],
          ),
          content: const Text(
            'Please select a template JSON file from your device.\n\nTemplate files are usually located in your Download folder.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, 'select'),
              child: const Text('Select File'),
            ),
          ],
        ),
      );

      if (result == 'select') {
        _selectAndImportTemplateFile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error: $e')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectAndImportTemplateFile() async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Please select template file...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Use file_picker to select JSON file
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (mounted) {
        Navigator.pop(context); // Close loading
      }

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        await _importTemplateFromFile(filePath);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading if still open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error selecting file: $e')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _importTemplateFromFile(String filePath) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading template...'),
                ],
              ),
            ),
          ),
        ),
      );

      final templateService = ProjectTemplateService();
      final templateData = await templateService.loadTemplateFromFile(filePath);

      if (mounted) {
        Navigator.pop(context); // Close loading

        // Get current user
        final user = await _authService.getUser();
        final username = user?.username ?? 'unknown';

        // Create project from template
        final project = templateService.importFromTemplate(templateData, username);

        // Navigate to create screen with pre-filled data
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateProjectScreen(
              project: project,
              isFromTemplate: true,
            ),
          ),
        );

        if (result == true) {
          _loadProjects();
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Error importing template: $e')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToProjectDetail(Project project) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectDetailScreen(project: project),
      ),
    );

    if (result == true) {
      _loadProjects();
    }
  }
}
