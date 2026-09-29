import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/basemap_model.dart';
import 'crashlytics_service.dart';

import '../utils/app_logger.dart';
class BasemapService {
  static const String _basemapsKey = 'basemaps';
  static const String _selectedBasemapKey = 'selected_basemap';

  // Get all basemaps (default + custom + pdf)
  Future<List<Basemap>> getBasemaps() async {
    final prefs = await SharedPreferences.getInstance();
    final basemapsJson = prefs.getString(_basemapsKey);
    
    List<Basemap> customBasemaps = [];
    if (basemapsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(basemapsJson);
        customBasemaps = decoded.map((json) => Basemap.fromJson(json)).toList();
        logDebug('📦 Loaded ${customBasemaps.length} custom/PDF basemaps from storage', tag: 'BASEMAP');
        
        // Debug: Print each basemap
        for (var basemap in customBasemaps) {
          logDebug('   - ${basemap.name} (${basemap.type})', tag: 'BASEMAP');
          if (basemap.type == BasemapType.pdf) {
            logDebug('     useOverlayMode: ${basemap.useOverlayMode}', tag: 'BASEMAP');
            logDebug('     pdfOverlayImagePath: ${basemap.pdfOverlayImagePath}', tag: 'BASEMAP');
            logDebug('     hasPdfGeoreferencing: ${basemap.hasPdfGeoreferencing}', tag: 'BASEMAP');
            if (basemap.hasPdfGeoreferencing) {
              logDebug('     Bounds: [${basemap.pdfMinLat}, ${basemap.pdfMinLon}] to [${basemap.pdfMaxLat}, ${basemap.pdfMaxLon}]', tag: 'BASEMAP');
            }
          }
        }
      } catch (e, stack) {
        logError('❌ Error loading basemaps: $e', tag: 'BASEMAP');
        crashlytics.recordError(e, stack, reason: 'Map: Error loading basemaps');
      }
    }
    
    return [...Basemap.getDefaultBasemaps(), ...customBasemaps];
  }

  // Save custom or PDF basemap
  Future<void> saveBasemap(Basemap basemap) async {
    logDebug('💾 Saving basemap: ${basemap.name} (${basemap.type})', tag: 'BASEMAP');
    
    final prefs = await SharedPreferences.getInstance();
    final basemaps = await getBasemaps();
    
    // Remove default basemaps before saving (only save custom and PDF)
    final customBasemaps = basemaps
        .where((b) => b.type == BasemapType.custom || b.type == BasemapType.pdf)
        .toList();
    
    // Check if basemap already exists
    final index = customBasemaps.indexWhere((b) => b.id == basemap.id);
    if (index >= 0) {
      logDebug('   Updating existing basemap at index $index', tag: 'BASEMAP');
      customBasemaps[index] = basemap;
    } else {
      logDebug('   Adding new basemap', tag: 'BASEMAP');
      customBasemaps.add(basemap);
    }
    
    final basemapsJson = jsonEncode(customBasemaps.map((b) => b.toJson()).toList());
    await prefs.setString(_basemapsKey, basemapsJson);
    logDebug('✅ Basemap saved successfully', tag: 'BASEMAP');
  }

  // Delete custom or PDF basemap
  Future<void> deleteBasemap(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final basemaps = await getBasemaps();
    
    final customBasemaps = basemaps
        .where((b) => (b.type == BasemapType.custom || b.type == BasemapType.pdf) && b.id != id)
        .toList();
    
    final basemapsJson = jsonEncode(customBasemaps.map((b) => b.toJson()).toList());
    await prefs.setString(_basemapsKey, basemapsJson);
  }

  // Get selected basemap
  Future<Basemap> getSelectedBasemap() async {
    final prefs = await SharedPreferences.getInstance();
    final selectedId = prefs.getString(_selectedBasemapKey);
    
    final basemaps = await getBasemaps();
    
    logDebug('🗺️ Getting selected basemap...', tag: 'BASEMAP');
    logDebug('   Selected ID: $selectedId', tag: 'BASEMAP');
    logDebug('   Available basemaps: ${basemaps.length}', tag: 'BASEMAP');
    
    if (selectedId != null) {
      final basemap = basemaps.where((b) => b.id == selectedId).firstOrNull;
      if (basemap != null) {
        logDebug('   ✅ Found selected basemap: ${basemap.name} (${basemap.type})', tag: 'BASEMAP');
        if (basemap.type == BasemapType.pdf) {
          logDebug('      useOverlayMode: ${basemap.useOverlayMode}', tag: 'BASEMAP');
          logDebug('      pdfOverlayImagePath: ${basemap.pdfOverlayImagePath}', tag: 'BASEMAP');
          logDebug('      hasPdfGeoreferencing: ${basemap.hasPdfGeoreferencing}', tag: 'BASEMAP');
        }
        return basemap;
      }
    }
    
    // Return default basemap
    logWarn('   ⚠️ No valid selection, returning default basemap', tag: 'BASEMAP');
    return basemaps.firstWhere((b) => b.isDefault);
  }

  // Set selected basemap
  Future<void> setSelectedBasemap(String id) async {
    logDebug('📌 Setting selected basemap to: $id', tag: 'BASEMAP');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedBasemapKey, id);
  }
}
