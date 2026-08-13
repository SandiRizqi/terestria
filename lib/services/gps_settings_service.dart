import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/settings/gps_settings.dart';
import '../utils/app_logger.dart';

/// Penyimpan runtime setelan GPS. Mirror pola [SettingsService], tapi model
/// murni Dart agar snapshot-nya bisa dibaca ulang dari isolate background.
///
/// Kunci prefs [prefsKey] menyimpan blob JSON; isolate memakai
/// [GpsSettingsService.loadFromPrefs] untuk membaca snapshot yang sama.
class GpsSettingsService {
  static final GpsSettingsService _instance = GpsSettingsService._internal();
  factory GpsSettingsService() => _instance;
  GpsSettingsService._internal();

  static const String prefsKey = 'gps_settings';

  GpsSettings _settings = GpsSettings.defaults();
  GpsSettings get settings => _settings;

  Future<void> initialize() async {
    _settings = await loadFromPrefs();
  }

  /// Baca setelan dari SharedPreferences (dipakai juga oleh isolate). Selalu
  /// mengembalikan objek valid — default bila belum ada / gagal parse.
  static Future<GpsSettings> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw == null) return GpsSettings.defaults();
      return GpsSettings.fromJson(json.decode(raw) as Map<String, dynamic>);
    } catch (e) {
      logError('❌ GpsSettingsService: gagal load ($e) — pakai default');
      return GpsSettings.defaults();
    }
  }

  Future<void> save(GpsSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Lewatkan JSON→model sekali agar tersimpan sudah ter-clamp.
      final clamped = GpsSettings.fromJson(settings.toJson());
      await prefs.setString(prefsKey, json.encode(clamped.toJson()));
      _settings = clamped;
    } catch (e) {
      logError('❌ GpsSettingsService: gagal simpan ($e)');
      rethrow;
    }
  }

  Future<void> update(GpsSettings settings) => save(settings);

  Future<void> resetToDefaults() => save(GpsSettings.defaults());
}
