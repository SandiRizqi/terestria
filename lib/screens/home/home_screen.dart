import 'package:flutter/material.dart';
import '../../models/project_model.dart';
import '../../services/storage_service.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';
import '../project/create_project_screen.dart';
import '../project/project_detail_screen.dart';
import '../basemap/basemap_management_screen.dart';
import '../../widgets/project_card.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';
import '../../widgets/search_bar.dart' as custom;

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StorageService _storageService = StorageService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  
  List<Project> _projects = [];
  List<Project> _filteredProjects = [];
  bool _isLoading = true;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
          final searchLower = query.toLowerCase();
          return nameLower.contains(searchLower) || descLower.contains(searchLower);
        }).toList();
      }
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching 
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.black45),
                decoration: const InputDecoration(
                  hintText: 'Search projects...',
                  hintStyle: TextStyle(color: Colors.black45),
                  border: InputBorder.none,
                ),
                onChanged: _filterProjects,
              )
            : const Text('Terestria'),
        actions: [
          if (!_isSearching) ...[
            const ConnectivityIndicator(
              showLabel: false,
              iconSize: 24,
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search Projects',
              onPressed: () {
                setState(() => _isSearching = true);
              },
            ),
            IconButton(
              icon: const Icon(Icons.map),
              tooltip: 'Basemap Management',
              onPressed: () => _navigateToBasemapManagement(),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'about') {
                  _showAboutDialog();
                } else if (value == 'logout') {
                  _logout();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'about',
                  child: Row(
                    children: [
                      Icon(Icons.info_outline),
                      SizedBox(width: 12),
                      Text('About'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: Colors.red),
                      SizedBox(width: 12),
                      Text('Logout', style: TextStyle(color: Colors.red)),
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
          // Connectivity Banner
          const Padding(
            padding: EdgeInsets.all(12.0),
            child: ConnectivityIndicator(showLabel: true),
          ),
          
          // Project List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProjects.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadProjects,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredProjects.length,
                          itemBuilder: (context, index) {
                            final project = _filteredProjects[index];
                            return ProjectCard(
                              project: project,
                              onTap: () => _navigateToProjectDetail(project),
                              onDelete: () => _deleteProject(project),
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
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreateProjectScreen(),
      ),
    );

    if (result == true) {
      _loadProjects();
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

  void _navigateToBasemapManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const BasemapManagementScreen(),
      ),
    );
  }

  void _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _authService.logout();
        
        if (mounted) {
          // Navigate to login screen and clear stack
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
          );
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logged out successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error during logout: $e')),
          );
        }
      }
    }
  }

  void _showAboutDialog() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.eco, size: 32, color: Colors.green),
            SizedBox(width: 12),
            Text('Terestria'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Version 1.0.0',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Agricultural and Environmental Mapping App',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'A professional geospatial data collection platform designed for agricultural and environmental field surveys.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Key Features:\n'
                '• Custom survey forms\n'
                '• Point, Line & Polygon mapping\n'
                '• Real-time GPS tracking\n'
                '• Offline functionality\n'
                '• Multiple basemap support\n'
                '• Data export capabilities',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      );
    },
  );
}
}
