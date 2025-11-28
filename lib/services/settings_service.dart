import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/settings/app_settings.dart';

class SettingsService extends ChangeNotifier {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _settingsKey = 'app_settings';
  AppSettings _settings = AppSettings.defaults();

  AppSettings get settings => _settings;

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
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading settings: $e');
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
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving settings: $e');
      rethrow;
    }
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
