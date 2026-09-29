import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/settings/app_settings.dart';
import 'tracking/tracking_session_manager.dart';

import '../utils/app_logger.dart';
class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _settingsKey = 'app_settings';
  AppSettings _settings = AppSettings.defaults();

  AppSettings get settings => _settings;

  /// Notifier untuk ThemeMode — di-listen oleh MaterialApp di main.dart.
  final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier(ThemeMode.light);

  // Initialize settings from storage
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = prefs.getString(_settingsKey);
      
      if (settingsJson != null) {
        final map = json.decode(settingsJson) as Map<String, dynamic>;
        _settings = AppSettings.fromJson(map);
      } else {
        _settings = AppSettings.defaults();
      }

      // Sync theme mode notifier setelah load
      themeModeNotifier.value =
          _settings.darkMode ? ThemeMode.dark : ThemeMode.light;
      // Selaraskan batas tracking bersamaan ke manajer sesi.
      TrackingSessionManager.instance.maxConcurrent =
          _settings.maxConcurrentTracking;

      notifyListeners();
    } catch (e) {
      logWarn('Error loading settings: $e', tag: 'CONFIG');
      _settings = AppSettings.defaults();
    }
  }

  // Save settings to storage
  Future<void> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsJson = json.encode(settings.toJson());
      await prefs.setString(_settingsKey, settingsJson);

      _settings = settings;
      // Sync theme mode notifier setiap kali settings disimpan
      themeModeNotifier.value =
          _settings.darkMode ? ThemeMode.dark : ThemeMode.light;
      TrackingSessionManager.instance.maxConcurrent =
          _settings.maxConcurrentTracking;
      notifyListeners();
    } catch (e) {
      logWarn('Error saving settings: $e', tag: 'CONFIG');
      rethrow;
    }
  }

  // Update dark mode
  Future<void> updateDarkMode(bool isDark) async {
    await saveSettings(_settings.copyWith(darkMode: isDark));
  }

  // Update watermark foto
  Future<void> updatePhotoWatermark(bool enabled) async {
    await saveSettings(_settings.copyWith(photoWatermark: enabled));
  }

  // Update batas project tracking bersamaan (clamp 3..7)
  Future<void> updateMaxConcurrentTracking(int value) async {
    final clamped = value.clamp(
      AppSettings.minConcurrentTracking,
      AppSettings.maxConcurrentTrackingLimit,
    );
    await saveSettings(_settings.copyWith(maxConcurrentTracking: clamped));
  }

  // Update specific setting
  Future<void> updateAreaUnit(AreaUnit unit) async {
    await saveSettings(_settings.copyWith(areaUnit: unit));
  }

  Future<void> updateLengthUnit(LengthUnit unit) async {
    await saveSettings(_settings.copyWith(lengthUnit: unit));
  }

  Future<void> updatePointColor(Color color) async {
    await saveSettings(_settings.copyWith(pointColor: color));
  }

  Future<void> updateLineColor(Color color) async {
    await saveSettings(_settings.copyWith(lineColor: color));
  }

  Future<void> updatePolygonColor(Color color) async {
    await saveSettings(_settings.copyWith(polygonColor: color));
  }

  Future<void> updatePdfDpi(int dpi) async {
    await saveSettings(_settings.copyWith(pdfDpi: dpi));
  }

  Future<void> updatePointSize(double size) async {
    await saveSettings(_settings.copyWith(pointSize: size));
  }

  Future<void> updateLineWidth(double width) async {
    await saveSettings(_settings.copyWith(lineWidth: width));
  }

  Future<void> updatePolygonOpacity(double opacity) async {
    await saveSettings(_settings.copyWith(polygonOpacity: opacity));
  }

  // Reset to defaults
  Future<void> resetToDefaults() async {
    await saveSettings(AppSettings.defaults());
  }
}
