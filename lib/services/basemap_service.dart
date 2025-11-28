import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/basemap_model.dart';

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
        print('📦 Loaded ${customBasemaps.length} custom/PDF basemaps from storage');
        
        // Debug: Print each basemap
        for (var basemap in customBasemaps) {
          print('   - ${basemap.name} (${basemap.type})');
          if (basemap.type == BasemapType.pdf) {
            print('     useOverlayMode: ${basemap.useOverlayMode}');
            print('     pdfOverlayImagePath: ${basemap.pdfOverlayImagePath}');
            print('     hasPdfGeoreferencing: ${basemap.hasPdfGeoreferencing}');
            if (basemap.hasPdfGeoreferencing) {
              print('     Bounds: [${basemap.pdfMinLat}, ${basemap.pdfMinLon}] to [${basemap.pdfMaxLat}, ${basemap.pdfMaxLon}]');
            }
          }
        }
      } catch (e) {
        print('❌ Error loading basemaps: $e');
      }
    }
    
    return [...Basemap.getDefaultBasemaps(), ...customBasemaps];
  }

  // Save custom or PDF basemap
  Future<void> saveBasemap(Basemap basemap) async {
    print('💾 Saving basemap: ${basemap.name} (${basemap.type})');
    
    final prefs = await SharedPreferences.getInstance();
    final basemaps = await getBasemaps();
    
    // Remove default basemaps before saving (only save custom and PDF)
    final customBasemaps = basemaps
        .where((b) => b.type == BasemapType.custom || b.type == BasemapType.pdf)
        .toList();
    
    // Check if basemap already exists
    final index = customBasemaps.indexWhere((b) => b.id == basemap.id);
    if (index >= 0) {
      print('   Updating existing basemap at index $index');
      customBasemaps[index] = basemap;
    } else {
      print('   Adding new basemap');
      customBasemaps.add(basemap);
    }
    
    final basemapsJson = jsonEncode(customBasemaps.map((b) => b.toJson()).toList());
    await prefs.setString(_basemapsKey, basemapsJson);
    print('✅ Basemap saved successfully');
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
    
    print('🗺️ Getting selected basemap...');
    print('   Selected ID: $selectedId');
    print('   Available basemaps: ${basemaps.length}');
    
    if (selectedId != null) {
      final basemap = basemaps.where((b) => b.id == selectedId).firstOrNull;
      if (basemap != null) {
        print('   ✅ Found selected basemap: ${basemap.name} (${basemap.type})');
        if (basemap.type == BasemapType.pdf) {
          print('      useOverlayMode: ${basemap.useOverlayMode}');
          print('      pdfOverlayImagePath: ${basemap.pdfOverlayImagePath}');
          print('      hasPdfGeoreferencing: ${basemap.hasPdfGeoreferencing}');
        }
        return basemap;
      }
    }
    
    // Return default basemap
    print('   ⚠️ No valid selection, returning default basemap');
    return basemaps.firstWhere((b) => b.isDefault);
  }

  // Set selected basemap
  Future<void> setSelectedBasemap(String id) async {
    print('📌 Setting selected basemap to: $id');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedBasemapKey, id);
  }
}
