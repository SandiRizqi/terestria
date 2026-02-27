import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class PinnedValuesService {
  static const String _prefix = 'pinned_';

  String _key(String projectId, String fieldLabel) {
    return '${_prefix}${projectId}_${fieldLabel}';
  }

  /// Load semua pinned values untuk satu project.
  /// Returns Map<fieldLabel, value>
  Future<Map<String, dynamic>> loadPinnedValues(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith('${_prefix}${projectId}_'));
    final result = <String, dynamic>{};

    for (final key in keys) {
      // Extract field label dari key
      final fieldLabel = key.substring('${_prefix}${projectId}_'.length);
      final raw = prefs.getString(key);
      if (raw != null) {
        try {
          result[fieldLabel] = json.decode(raw);
        } catch (_) {
          result[fieldLabel] = raw;
        }
      }
    }
    return result;
  }

  /// Simpan pinned value untuk satu field
  Future<void> savePinnedValue(
      String projectId, String fieldLabel, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(projectId, fieldLabel), json.encode(value));
  }

  /// Hapus pinned value untuk satu field (unpin)
  Future<void> removePinnedValue(String projectId, String fieldLabel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(projectId, fieldLabel));
  }

  /// Cek apakah field sudah di-pin
  Future<bool> isPinned(String projectId, String fieldLabel) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key(projectId, fieldLabel));
  }

  // ─────────────────────────────────────────────
  // Case mode persistence
  // Key format: casemode_{projectId}_{fieldLabel}
  // ─────────────────────────────────────────────

  String _caseKey(String projectId, String fieldLabel) {
    return 'casemode_${projectId}_${fieldLabel}';
  }

  /// Simpan case mode untuk satu field ('normal' | 'upper' | 'lower')
  Future<void> saveCaseMode(
      String projectId, String fieldLabel, String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_caseKey(projectId, fieldLabel), mode);
  }

  /// Load semua case modes untuk satu project.
  /// Returns Map<fieldLabel, modeString>
  Future<Map<String, String>> loadCaseModes(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'casemode_${projectId}_';
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix));
    final result = <String, String>{};
    for (final key in keys) {
      final fieldLabel = key.substring(prefix.length);
      final val = prefs.getString(key);
      if (val != null) result[fieldLabel] = val;
    }
    return result;
  }

  /// Hapus case mode untuk satu field (reset ke normal)
  Future<void> removeCaseMode(String projectId, String fieldLabel) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_caseKey(projectId, fieldLabel));
  }
}
