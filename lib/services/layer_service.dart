import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/layer_model.dart';

/// Service to manage GeoJSON layers: persistence, file import, and helpers.
class LayerService {
  static const _prefKey = 'geojson_layers_v1';
  static const _dirName = 'geojson_layers';

  // ──────────────────────────────────────────────────────
  // CRUD
  // ──────────────────────────────────────────────────────

  /// Load all saved layers (in creation order, newest first).
  Future<List<LayerModel>> loadLayers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefKey) ?? [];
    final layers = <LayerModel>[];
    for (final item in raw) {
      try {
        layers.add(LayerModel.fromJson(jsonDecode(item) as Map<String, dynamic>));
      } catch (_) {
        // skip corrupted entries
      }
    }
    // newest first
    layers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return layers;
  }

  /// Save (insert or update) a layer.
  Future<void> saveLayer(LayerModel layer) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefKey) ?? [];

    final list = raw.map((e) {
      try {
        return LayerModel.fromJson(jsonDecode(e) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<LayerModel>().toList();

    final idx = list.indexWhere((l) => l.id == layer.id);
    if (idx >= 0) {
      list[idx] = layer;
    } else {
      list.add(layer);
    }

    await prefs.setStringList(
        _prefKey, list.map((l) => jsonEncode(l.toJson())).toList());
  }

  /// Delete a layer (removes metadata AND the copied GeoJSON file).
  Future<void> deleteLayer(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefKey) ?? [];

    final list = raw.map((e) {
      try {
        return LayerModel.fromJson(jsonDecode(e) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<LayerModel>().toList();

    final target = list.firstWhere((l) => l.id == id,
        orElse: () => throw StateError('Layer not found'));

    // Delete the file
    try {
      final f = File(target.filePath);
      if (await f.exists()) await f.delete();
    } catch (_) {}

    list.removeWhere((l) => l.id == id);
    await prefs.setStringList(
        _prefKey, list.map((l) => jsonEncode(l.toJson())).toList());
  }

  /// Toggle the active/visible state of a layer.
  Future<void> toggleLayer(String id, bool active) async {
    final layers = await loadLayers();
    final idx = layers.indexWhere((l) => l.id == id);
    if (idx < 0) return;
    layers[idx] = layers[idx].copyWith(isActive: active);
    await saveLayer(layers[idx]);
  }

  // ──────────────────────────────────────────────────────
  // File helpers
  // ──────────────────────────────────────────────────────

  /// Copy the picked GeoJSON file to the app's private storage.
  /// Returns the new internal path.
  Future<String> importGeoJsonFile(String sourcePath, String layerId) async {
    final dir = await _layerDirectory();
    final dest = File('${dir.path}/$layerId.geojson');
    final src = File(sourcePath);
    await src.copy(dest.path);
    return dest.path;
  }

  /// Read and parse a GeoJSON file; returns null on any error.
  Future<Map<String, dynamic>?> readGeoJson(String filePath) async {
    try {
      final content = await File(filePath).readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _layerDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ──────────────────────────────────────────────────────
  // Static helpers
  // ──────────────────────────────────────────────────────

  /// Detect dominant geometry type from a GeoJSON FeatureCollection.
  static String detectGeometryType(Map<String, dynamic> geoJson) {
    final features = geoJson['features'] as List<dynamic>? ?? [];
    if (features.isEmpty) return 'Point';

    final types = <String>{};
    for (final f in features) {
      final geom = (f as Map<String, dynamic>)['geometry'] as Map<String, dynamic>?;
      if (geom == null) continue;
      final t = geom['type'] as String? ?? '';
      // Normalise multi-types
      if (t.startsWith('Multi')) {
        types.add(t.substring(5)); // e.g. 'MultiPolygon' → 'Polygon'
      } else {
        types.add(t);
      }
    }

    if (types.length == 1) {
      // Only one type → return as-is but prefer canonical names
      switch (types.first) {
        case 'Point':
          return 'Point';
        case 'LineString':
          return 'LineString';
        case 'Polygon':
          return 'Polygon';
      }
    }
    // Mixed
    return 'Mixed';
  }

  /// Extract the set of property keys from the first N features.
  static List<String> detectPropertyKeys(Map<String, dynamic> geoJson,
      {int sampleSize = 20}) {
    final features = geoJson['features'] as List<dynamic>? ?? [];
    final keys = <String>{};
    for (final f in features.take(sampleSize)) {
      final props =
          (f as Map<String, dynamic>)['properties'] as Map<String, dynamic>? ??
              {};
      keys.addAll(props.keys);
    }
    return keys.toList()..sort();
  }
}
