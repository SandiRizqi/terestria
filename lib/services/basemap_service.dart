import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/basemap_model.dart';

class BasemapService {
  static const String _basemapsKey = 'basemaps';
  static const String _selectedBasemapKey = 'selected_basemap';

  // Get all basemaps (default + custom)
  Future<List<Basemap>> getBasemaps() async {
    final prefs = await SharedPreferences.getInstance();
    final basemapsJson = prefs.getString(_basemapsKey);
    
    List<Basemap> customBasemaps = [];
    if (basemapsJson != null) {
      final List<dynamic> decoded = jsonDecode(basemapsJson);
      customBasemaps = decoded.map((json) => Basemap.fromJson(json)).toList();
    }
    
    return [...Basemap.getDefaultBasemaps(), ...customBasemaps];
  }

  // Save custom basemap
  Future<void> saveBasemap(Basemap basemap) async {
    final prefs = await SharedPreferences.getInstance();
    final basemaps = await getBasemaps();
    
    // Remove default basemaps before saving
    final customBasemaps = basemaps.where((b) => b.type == BasemapType.custom).toList();
    
    // Check if basemap already exists
    final index = customBasemaps.indexWhere((b) => b.id == basemap.id);
    if (index >= 0) {
      customBasemaps[index] = basemap;
    } else {
      customBasemaps.add(basemap);
    }
    
    final basemapsJson = jsonEncode(customBasemaps.map((b) => b.toJson()).toList());
    await prefs.setString(_basemapsKey, basemapsJson);
  }

  // Delete custom basemap
  Future<void> deleteBasemap(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final basemaps = await getBasemaps();
    
    final customBasemaps = basemaps
        .where((b) => b.type == BasemapType.custom && b.id != id)
        .toList();
    
    final basemapsJson = jsonEncode(customBasemaps.map((b) => b.toJson()).toList());
    await prefs.setString(_basemapsKey, basemapsJson);
  }

  // Get selected basemap
  Future<Basemap> getSelectedBasemap() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getString(_selectedBasemapKey);
    
    final basemaps = await getBasemaps();
    
    if (selectedId != null) {
      final basemap = basemaps.where((b) => b.id == selectedId).firstOrNull;
      if (basemap != null) return basemap;
    }
    
    // Return default basemap
    return basemaps.firstWhere((b) => b.isDefault);
  }

  // Set selected basemap
  Future<void> setSelectedBasemap(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedBasemapKey, id);
  }
}
