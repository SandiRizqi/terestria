import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project_model.dart';
import '../models/geo_data_model.dart';

class StorageService {
  static const String _projectsKey = 'projects';
  static const String _geoDataKey = 'geo_data';

  // Save Projects
  Future<void> saveProjects(List<Project> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = projects.map((p) => json.encode(p.toJson())).toList();
    await prefs.setStringList(_projectsKey, jsonList);
  }

  // Load Projects
  Future<List<Project>> loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = prefs.getStringList(_projectsKey) ?? [];
    return jsonList.map((j) => Project.fromJson(json.decode(j))).toList();
  }

  // Save single project
  Future<void> saveProject(Project project) async {
    final projects = await loadProjects();
    final index = projects.indexWhere((p) => p.id == project.id);
    
    if (index != -1) {
      projects[index] = project;
    } else {
      projects.add(project);
    }
    
    await saveProjects(projects);
  }

  // Delete project
  Future<void> deleteProject(String projectId) async {
    final projects = await loadProjects();
    projects.removeWhere((p) => p.id == projectId);
    await saveProjects(projects);
    
    // Also delete related geo data
    final geoDataList = await loadGeoData(projectId);
    for (var data in geoDataList) {
      await deleteGeoData(data.id);
    }
  }

  // Save GeoData
  Future<void> saveGeoData(GeoData geoData) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_geoDataKey}_${geoData.projectId}';
    final existingData = prefs.getStringList(key) ?? [];
    
    final index = existingData.indexWhere((d) {
      final decoded = json.decode(d);
      return decoded['id'] == geoData.id;
    });
    
    if (index != -1) {
      existingData[index] = json.encode(geoData.toJson());
    } else {
      existingData.add(json.encode(geoData.toJson()));
    }
    
    await prefs.setStringList(key, existingData);
  }

  // Load GeoData by project
  Future<List<GeoData>> loadGeoData(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_geoDataKey}_$projectId';
    final jsonList = prefs.getStringList(key) ?? [];
    return jsonList.map((j) => GeoData.fromJson(json.decode(j))).toList();
  }

  // Delete GeoData
  Future<void> deleteGeoData(String geoDataId) async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    
    for (var key in allKeys) {
      if (key.startsWith(_geoDataKey)) {
        final jsonList = prefs.getStringList(key) ?? [];
        jsonList.removeWhere((j) {
          final decoded = json.decode(j);
          return decoded['id'] == geoDataId;
        });
        await prefs.setStringList(key, jsonList);
      }
    }
  }

  // Export project data as JSON
  Future<Map<String, dynamic>> exportProject(String projectId) async {
    final projects = await loadProjects();
    final project = projects.firstWhere((p) => p.id == projectId);
    final geoDataList = await loadGeoData(projectId);
    
    return {
      'project': project.toJson(),
      'data': geoDataList.map((d) => d.toJson()).toList(),
    };
  }

  // Clear all data
  Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
