import '../models/project_model.dart';
import '../models/geo_data_model.dart';
import 'database_service.dart';

/// Storage Service - Now using SQLite for better performance and scalability
/// Migrated from SharedPreferences to handle large datasets efficiently
class StorageService {
  final DatabaseService _db = DatabaseService();

  // ==================== PROJECT OPERATIONS ====================

  /// Save or update a single project
  Future<void> saveProject(Project project) async {
    await _db.saveProject(project);
  }

  /// Save multiple projects (batch operation)
  Future<void> saveProjects(List<Project> projects) async {
    for (var project in projects) {
      await _db.saveProject(project);
    }
  }

  /// Load all projects
  Future<List<Project>> loadProjects() async {
    return await _db.loadProjects();
  }

  /// Get a single project by ID
  Future<Project?> getProjectById(String projectId) async {
    return await _db.getProjectById(projectId);
  }

  /// Delete a project and all its related geo data
  Future<void> deleteProject(String projectId) async {
    await _db.deleteProject(projectId);
  }

  /// Update project sync status
  Future<void> updateProjectSyncStatus(String projectId, bool isSynced, {DateTime? syncedAt}) async {
    await _db.updateProjectSyncStatus(projectId, isSynced, syncedAt: syncedAt);
  }

  /// Get all projects that haven't been synced to server
  Future<List<Project>> getUnsyncedProjects() async {
    return await _db.getUnsyncedProjects();
  }

  // ==================== GEO DATA OPERATIONS ====================

  /// Save or update a single geo data
  Future<void> saveGeoData(GeoData geoData) async {
    await _db.saveGeoData(geoData);
  }

  /// Load all geo data for a specific project
  Future<List<GeoData>> loadGeoData(String projectId) async {
    return await _db.loadGeoData(projectId);
  }

  /// Get a single geo data by ID
  Future<GeoData?> getGeoDataById(String geoDataId) async {
    return await _db.getGeoDataById(geoDataId);
  }

  /// Delete a single geo data
  Future<void> deleteGeoData(String geoDataId) async {
    await _db.deleteGeoData(geoDataId);
  }

  /// Update geo data sync status
  Future<void> updateGeoDataSyncStatus(String geoDataId, bool isSynced, {DateTime? syncedAt}) async {
    await _db.updateGeoDataSyncStatus(geoDataId, isSynced, syncedAt: syncedAt);
  }

  /// Get all unsynced geo data (optionally filtered by project)
  Future<List<GeoData>> getUnsyncedGeoData({String? projectId}) async {
    return await _db.getUnsyncedGeoData(projectId: projectId);
  }

  /// Get count of geo data for a project
  Future<int> getGeoDataCount(String projectId) async {
    return await _db.getGeoDataCount(projectId);
  }

  /// Get count of unsynced geo data (optionally filtered by project)
  Future<int> getUnsyncedGeoDataCount({String? projectId}) async {
    return await _db.getUnsyncedGeoDataCount(projectId: projectId);
  }

  // ==================== EXPORT & UTILITY ====================

  /// Export project and all its data as JSON
  Future<Map<String, dynamic>> exportProject(String projectId) async {
    return await _db.exportProject(projectId);
  }

  /// Clear all data (use with caution!)
  Future<void> clearAllData() async {
    await _db.clearAllData();
  }

  /// Close database connection
  Future<void> closeDatabase() async {
    await _db.closeDatabase();
  }
}
