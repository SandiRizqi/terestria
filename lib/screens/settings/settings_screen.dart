import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:io';
import '../../models/settings/app_settings.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsService _settingsService = SettingsService();
  late AppSettings _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _settingsService.initialize();
    setState(() {
      _settings = _settingsService.settings;
      _isLoading = false;
    });
  }

  Future<void> _showColorPicker({
    required String title,
    required Color currentColor,
    required Function(Color) onColorChanged,
  }) async {
    Color pickerColor = currentColor;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) => pickerColor = color,
            pickerAreaHeightPercent: 0.8,
            enableAlpha: false,
            displayThumbColor: true,
            paletteType: PaletteType.hsvWithHue,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              onColorChanged(pickerColor);
              Navigator.pop(context);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings'),
        content: const Text('Are you sure you want to reset all settings to default values?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
            ),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _settingsService.resetToDefaults();
      setState(() => _settings = _settingsService.settings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings reset to defaults')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Reset to Defaults',
            onPressed: _showResetDialog,
          ),
        ],
      ),
      body: ListView(
        children: [
          _buildHeader(),
          const SizedBox(height: 8),
          
          // Measurement Units Section
          _buildSectionTitle('Measurement Units'),
          _buildAreaUnitTile(),
          _buildLengthUnitTile(),
          
          const Divider(height: 32),
          
          // Map Colors Section
          _buildSectionTitle('Map Colors'),
          _buildColorTile(
            title: 'Point Color',
            subtitle: 'Color for point markers',
            color: _settings.pointColor,
            onTap: () => _showColorPicker(
              title: 'Select Point Color',
              currentColor: _settings.pointColor,
              onColorChanged: (color) async {
                await _settingsService.updatePointColor(color);
                setState(() => _settings = _settingsService.settings);
              },
            ),
          ),
          _buildColorTile(
            title: 'Line Color',
            subtitle: 'Color for line features',
            color: _settings.lineColor,
            onTap: () => _showColorPicker(
              title: 'Select Line Color',
              currentColor: _settings.lineColor,
              onColorChanged: (color) async {
                await _settingsService.updateLineColor(color);
                setState(() => _settings = _settingsService.settings);
              },
            ),
          ),
          _buildColorTile(
            title: 'Polygon Color',
            subtitle: 'Color for polygon features',
            color: _settings.polygonColor,
            onTap: () => _showColorPicker(
              title: 'Select Polygon Color',
              currentColor: _settings.polygonColor,
              onColorChanged: (color) async {
                await _settingsService.updatePolygonColor(color);
                setState(() => _settings = _settingsService.settings);
              },
            ),
          ),
          
          const Divider(height: 32),
          
          // Map Appearance Section
          _buildSectionTitle('Map Appearance'),
          _buildSliderTile(
            title: 'Point Size',
            subtitle: 'Size of point markers (${_settings.pointSize.toStringAsFixed(0)} px)',
            value: _settings.pointSize,
            min: 8.0,
            max: 24.0,
            divisions: 16,
            onChanged: (value) async {
              await _settingsService.updatePointSize(value);
              setState(() => _settings = _settingsService.settings);
            },
          ),
          _buildSliderTile(
            title: 'Line Width',
            subtitle: 'Width of line features (${_settings.lineWidth.toStringAsFixed(1)} px)',
            value: _settings.lineWidth,
            min: 1.0,
            max: 10.0,
            divisions: 18,
            onChanged: (value) async {
              await _settingsService.updateLineWidth(value);
              setState(() => _settings = _settingsService.settings);
            },
          ),
          _buildSliderTile(
            title: 'Polygon Opacity',
            subtitle: 'Transparency of polygon fill (${(_settings.polygonOpacity * 100).toStringAsFixed(0)}%)',
            value: _settings.polygonOpacity,
            min: 0.1,
            max: 1.0,
            divisions: 9,
            onChanged: (value) async {
              await _settingsService.updatePolygonOpacity(value);
              setState(() => _settings = _settingsService.settings);
            },
          ),
          
          const Divider(height: 32),
          
          // PDF Settings Section
          _buildSectionTitle('PDF Basemap Settings'),
          _buildPdfDpiTile(),
          
          const SizedBox(height: 24),
          
          // Preview Card
          _buildPreviewCard(),
          
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(gradient: AppTheme.primaryGradient),
      padding: const EdgeInsets.all(20),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'App Preferences',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Customize units, colors, and appearance',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.primaryColor,
        ),
      ),
    );
  }

  Widget _buildAreaUnitTile() {
    return ListTile(
      leading: const Icon(Icons.crop_square, color: AppTheme.primaryColor),
      title: const Text('Area Unit'),
      subtitle: Text(_settings.areaUnit.name),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => _showAreaUnitDialog(),
    );
  }

  Widget _buildLengthUnitTile() {
    return ListTile(
      leading: const Icon(Icons.straighten, color: AppTheme.primaryColor),
      title: const Text('Length Unit'),
      subtitle: Text(_settings.lengthUnit.name),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => _showLengthUnitDialog(),
    );
  }

  Future<void> _showAreaUnitDialog() async {
    final selected = await showDialog<AreaUnit>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Area Unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: AreaUnit.values.map((unit) {
            return RadioListTile<AreaUnit>(
              title: Text(unit.name),
              subtitle: Text(unit.symbol),
              value: unit,
              groupValue: _settings.areaUnit,
              onChanged: (value) => Navigator.pop(context, value),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null) {
      await _settingsService.updateAreaUnit(selected);
      setState(() => _settings = _settingsService.settings);
    }
  }

  Future<void> _showLengthUnitDialog() async {
    final selected = await showDialog<LengthUnit>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Length Unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: LengthUnit.values.map((unit) {
            return RadioListTile<LengthUnit>(
              title: Text(unit.name),
              subtitle: Text(unit.symbol),
              value: unit,
              groupValue: _settings.lengthUnit,
              onChanged: (value) => Navigator.pop(context, value),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null) {
      await _settingsService.updateLengthUnit(selected);
      setState(() => _settings = _settingsService.settings);
    }
  }

  Widget _buildColorTile({
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey[300]!, width: 2),
        ),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  Widget _buildSliderTile({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required Function(double) onChanged,
  }) {
    return Column(
      children: [
        ListTile(
          title: Text(title),
          subtitle: Text(subtitle),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: value.toStringAsFixed(1),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildPdfDpiTile() {
    return ListTile(
      leading: const Icon(Icons.picture_as_pdf, color: AppTheme.primaryColor),
      title: const Text('PDF Processing DPI'),
      subtitle: Text('${_settings.pdfDpi} DPI - ${_getDpiDescription()}'),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => _showPdfDpiDialog(),
    );
  }

  String _getDpiDescription() {
    if (_settings.pdfDpi <= 150) return 'Fast, Low quality';
    if (_settings.pdfDpi <= 200) return 'Balanced';
    if (_settings.pdfDpi <= 300) return 'High quality';
    return 'Very high quality, slower';
  }

  Future<void> _showPdfDpiDialog() async {
    final dpiOptions = Platform.isIOS 
        ? [150, 200, 250] // iOS: lebih konservatif
        : [150, 200, 250, 300]; // Android: bisa lebih tinggi

    final selected = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select PDF DPI'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (Platform.isIOS)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'iOS: Higher DPI may cause memory issues',
                        style: TextStyle(fontSize: 12, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            ...dpiOptions.map((dpi) {
              String description;
              if (dpi <= 150) description = 'Fast, Low quality';
              else if (dpi <= 200) description = 'Balanced (Recommended)';
              else if (dpi <= 250) description = 'High quality';
              else description = 'Very high quality, slower';

              return RadioListTile<int>(
                title: Text('$dpi DPI'),
                subtitle: Text(description),
                value: dpi,
                groupValue: _settings.pdfDpi,
                onChanged: (value) => Navigator.pop(context, value),
              );
            }).toList(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null) {
      await _settingsService.updatePdfDpi(selected);
      setState(() => _settings = _settingsService.settings);
    }
  }

  Widget _buildPreviewCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preview',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          
          // Point preview
          Row(
            children: [
              Container(
                width: _settings.pointSize * 2,
                height: _settings.pointSize * 2,
                decoration: BoxDecoration(
                  color: _settings.pointColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              const Text('Point Marker'),
            ],
          ),
          const SizedBox(height: 16),
          
          // Line preview
          Row(
            children: [
              Container(
                width: 60,
                height: _settings.lineWidth,
                decoration: BoxDecoration(
                  color: _settings.lineColor,
                  borderRadius: BorderRadius.circular(_settings.lineWidth / 2),
                ),
              ),
              const SizedBox(width: 16),
              const Text('Line Feature'),
            ],
          ),
          const SizedBox(height: 16),
          
          // Polygon preview
          Row(
            children: [
              Container(
                width: 60,
                height: 40,
                decoration: BoxDecoration(
                  color: _settings.polygonColor.withOpacity(_settings.polygonOpacity),
                  border: Border.all(color: _settings.polygonColor, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 16),
              const Text('Polygon Feature'),
            ],
          ),
          
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          
          // Measurement examples
          Text(
            'Area: ${_settings.formatArea(10000)}',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Distance: ${_settings.formatDistance(1500)}',
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }
}
