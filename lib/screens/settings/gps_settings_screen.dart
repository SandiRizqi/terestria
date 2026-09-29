import 'package:flutter/material.dart';

import '../../models/settings/gps_settings.dart';
import '../../services/gps_settings_service.dart';
import '../../services/location_service_v2.dart';
import '../../theme/app_theme.dart';

/// Layar pengaturan tuning GPS. Kontrol dasar tampil langsung; sisanya di balik
/// expander "Advanced". Perubahan disimpan ke [GpsSettingsService]; tombol
/// "Restart tracking now" menerapkannya ke sesi tracking yang sedang berjalan.
class GpsSettingsScreen extends StatefulWidget {
  const GpsSettingsScreen({Key? key}) : super(key: key);

  @override
  State<GpsSettingsScreen> createState() => _GpsSettingsScreenState();
}

class _GpsSettingsScreenState extends State<GpsSettingsScreen> {
  final GpsSettingsService _service = GpsSettingsService();
  final LocationServiceV2 _location = LocationServiceV2();
  GpsSettings _s = GpsSettings.defaults();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _service.initialize();
    if (mounted) {
      setState(() {
        _s = _service.settings;
        _loading = false;
      });
    }
  }

  Future<void> _save(GpsSettings next) async {
    setState(() => _s = next);
    await _service.update(next);
  }

  Future<void> _reset() async {
    await _service.resetToDefaults();
    if (mounted) setState(() => _s = _service.settings);
    _snack('GPS settings reset to defaults');
  }

  Future<void> _restartTracking() async {
    _snack('Applying settings — restarting tracking…');
    try {
      await _location.restartTracking();
      _snack('Settings applied to tracking');
    } catch (e) {
      _snack('Failed to restart tracking: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : AppTheme.primaryGreen,
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('GPS & Location Accuracy')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryGreen,
        title: const Text('GPS & Location Accuracy',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore_rounded),
            tooltip: 'Reset to defaults',
            onPressed: _reset,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _sectionTitle('Basic'),
            _card([
              _sliderTile(
                title: 'Accuracy filter',
                subtitle: 'Drop fixes worse than this',
                value: _s.maxAccuracyMeters,
                min: GpsSettings.maxAccuracyMin,
                max: GpsSettings.maxAccuracyMax,
                unit: 'm',
                onChanged: (v) => _save(_s.copyWith(maxAccuracyMeters: v)),
              ),
              _divider(),
              _sliderTile(
                title: 'Smoothing (Kalman Q)',
                subtitle: 'Lower = smoother track, higher = more responsive',
                value: _s.kalmanQMetersPerSecond,
                min: GpsSettings.kalmanQMin,
                max: GpsSettings.kalmanQMax,
                fractionDigits: 1,
                unit: 'm/s',
                onChanged: (v) =>
                    _save(_s.copyWith(kalmanQMetersPerSecond: v)),
              ),
              _divider(),
              _sliderTile(
                title: 'Static-noise',
                subtitle: 'Drop movement below this (anti-jitter when still)',
                value: _s.staticNoiseThresholdMeters,
                min: GpsSettings.staticNoiseMin,
                max: GpsSettings.staticNoiseMax,
                fractionDigits: 1,
                unit: 'm',
                onChanged: (v) =>
                    _save(_s.copyWith(staticNoiseThresholdMeters: v)),
              ),
              _divider(),
              _sliderTile(
                title: 'Max realistic speed',
                subtitle: 'Above this is treated as a GPS spike and dropped',
                value: _s.maxRealisticSpeedKmh,
                min: GpsSettings.maxSpeedMin,
                max: GpsSettings.maxSpeedMax,
                unit: 'km/h',
                onChanged: (v) => _save(_s.copyWith(maxRealisticSpeedKmh: v)),
              ),
            ]),
            _sectionTitle('Advanced'),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: AppTheme.getCardDecoration,
              child: Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                title: const Text('Advanced settings',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                childrenPadding: EdgeInsets.zero,
                children: [
                  SwitchListTile(
                    title: const Text('Accept all until good fix'),
                    subtitle: const Text(
                        'Don\'t drop readings before the first good fix'),
                    value: _s.acceptAllUntilGoodFix,
                    activeColor: AppTheme.primaryGreen,
                    onChanged: (v) =>
                        _save(_s.copyWith(acceptAllUntilGoodFix: v)),
                  ),
                  SwitchListTile(
                    title: const Text('Record raw positions'),
                    subtitle: const Text(
                        'Save unsmoothed GPS positions in tracks (sharper corners). '
                        'Smoothing is still used for the map marker.'),
                    value: _s.recordRawPositions,
                    activeColor: AppTheme.primaryGreen,
                    onChanged: (v) =>
                        _save(_s.copyWith(recordRawPositions: v)),
                  ),
                  SwitchListTile(
                    title: const Text('Record only after good fix'),
                    subtitle: const Text(
                        'Warm-up: start recording the track after the first good fix'),
                    value: _s.warmupRequireGoodFix,
                    activeColor: AppTheme.primaryGreen,
                    onChanged: (v) =>
                        _save(_s.copyWith(warmupRequireGoodFix: v)),
                  ),
                  _sliderTile(
                    title: 'Outlier tolerance (k × accuracy)',
                    subtitle: 'Higher tolerates bigger jumps before rejecting',
                    value: _s.outlierAccuracyK,
                    min: GpsSettings.outlierKMin,
                    max: GpsSettings.outlierKMax,
                    fractionDigits: 1,
                    onChanged: (v) => _save(_s.copyWith(outlierAccuracyK: v)),
                  ),
                  _sliderTile(
                    title: 'Stationary hold (× accuracy)',
                    subtitle: 'Freeze track when movement is below this × accuracy',
                    value: _s.stationaryAccuracyFactor,
                    min: GpsSettings.stationaryFactorMin,
                    max: GpsSettings.stationaryFactorMax,
                    fractionDigits: 1,
                    onChanged: (v) =>
                        _save(_s.copyWith(stationaryAccuracyFactor: v)),
                  ),
                  _sliderTile(
                    title: 'Good-fix threshold',
                    value: _s.goodFixThresholdMeters,
                    min: GpsSettings.goodFixMin,
                    max: GpsSettings.goodFixMax,
                    unit: 'm',
                    onChanged: (v) =>
                        _save(_s.copyWith(goodFixThresholdMeters: v)),
                  ),
                  _sliderTile(
                    title: 'Drops before relaxing',
                    subtitle: 'Anti-freeze when signal degrades',
                    value: _s.poorAccuracyDropsBeforeRelax.toDouble(),
                    min: GpsSettings.poorDropsMin.toDouble(),
                    max: GpsSettings.poorDropsMax.toDouble(),
                    fractionDigits: 0,
                    onChanged: (v) => _save(
                        _s.copyWith(poorAccuracyDropsBeforeRelax: v.round())),
                  ),
                  _sliderTile(
                    title: 'Relaxed-mode accuracy cap (×)',
                    subtitle: 'Accept limit when degraded = Accuracy filter × this',
                    value: _s.relaxedAccuracyMultiplier,
                    min: GpsSettings.relaxedMultMin,
                    max: GpsSettings.relaxedMultMax,
                    fractionDigits: 1,
                    unit: '×',
                    onChanged: (v) =>
                        _save(_s.copyWith(relaxedAccuracyMultiplier: v)),
                  ),
                  _sliderTile(
                    title: 'Distance filter',
                    subtitle: 'Minimum distance before a new update',
                    value: _s.distanceFilterMeters,
                    min: GpsSettings.distanceFilterMin,
                    max: GpsSettings.distanceFilterMax,
                    fractionDigits: 1,
                    unit: 'm',
                    onChanged: (v) =>
                        _save(_s.copyWith(distanceFilterMeters: v)),
                  ),
                  _sliderTile(
                    title: 'Static-noise window',
                    value: _s.staticNoiseWindowSeconds.toDouble(),
                    min: GpsSettings.staticWindowMin.toDouble(),
                    max: GpsSettings.staticWindowMax.toDouble(),
                    fractionDigits: 0,
                    unit: 's',
                    onChanged: (v) => _save(
                        _s.copyWith(staticNoiseWindowSeconds: v.round())),
                  ),
                  _sliderTile(
                    title: 'Tracking interval',
                    value: _s.trackingIntervalMs.toDouble(),
                    min: GpsSettings.trackingIntervalMin.toDouble(),
                    max: GpsSettings.trackingIntervalMax.toDouble(),
                    fractionDigits: 0,
                    unit: 'ms',
                    onChanged: (v) =>
                        _save(_s.copyWith(trackingIntervalMs: v.round())),
                  ),
                  _sliderTile(
                    title: 'Single-shot timeout',
                    value: _s.getCurrentTimeoutSeconds.toDouble(),
                    min: GpsSettings.getCurrentTimeoutMin.toDouble(),
                    max: GpsSettings.getCurrentTimeoutMax.toDouble(),
                    fractionDigits: 0,
                    unit: 's',
                    onChanged: (v) => _save(
                        _s.copyWith(getCurrentTimeoutSeconds: v.round())),
                  ),
                  _sliderTile(
                    title: 'Emlid considered stale',
                    value: _s.emlidStaleSeconds.toDouble(),
                    min: GpsSettings.emlidStaleMin.toDouble(),
                    max: GpsSettings.emlidStaleMax.toDouble(),
                    fractionDigits: 0,
                    unit: 's',
                    onChanged: (v) =>
                        _save(_s.copyWith(emlidStaleSeconds: v.round())),
                  ),
                  _sliderTile(
                    title: 'Max last-known age',
                    value: _s.maxLastKnownAgeSeconds.toDouble(),
                    min: GpsSettings.lastKnownAgeMin.toDouble(),
                    max: GpsSettings.lastKnownAgeMax.toDouble(),
                    fractionDigits: 0,
                    unit: 's',
                    onChanged: (v) =>
                        _save(_s.copyWith(maxLastKnownAgeSeconds: v.round())),
                  ),
                  _sliderTile(
                    title: 'Coordinate decimals',
                    subtitle: '6 ≈ 11 cm',
                    value: _s.coordinateDecimals.toDouble(),
                    min: GpsSettings.coordinateDecimalsMin.toDouble(),
                    max: GpsSettings.coordinateDecimalsMax.toDouble(),
                    fractionDigits: 0,
                    onChanged: (v) =>
                        _save(_s.copyWith(coordinateDecimals: v.round())),
                  ),
                ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
              child: ElevatedButton.icon(
                onPressed: _restartTracking,
                icon: const Icon(Icons.refresh),
                label: const Text('Restart tracking now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Changes apply automatically when tracking next starts. '
                'Tap the button above to apply now.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Text(t,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.primaryColor,
                letterSpacing: 0.5)),
      );

  Widget _card(List<Widget> children) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: AppTheme.getCardDecoration,
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: children),
        ),
      );

  Widget _divider() => const Divider(height: 1, indent: 16, endIndent: 16);

  Widget _sliderTile({
    required String title,
    String? subtitle,
    required double value,
    required double min,
    required double max,
    int fractionDigits = 0,
    String unit = '',
    required ValueChanged<double> onChanged,
  }) {
    final label = '${value.toStringAsFixed(fractionDigits)}'
        '${unit.isEmpty ? '' : ' $unit'}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: subtitle == null ? null : Text(subtitle,
              style: const TextStyle(fontSize: 12)),
          trailing: Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppTheme.primaryColor)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            label: label,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
