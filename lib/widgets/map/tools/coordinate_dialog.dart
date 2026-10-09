import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme/app_theme.dart';
import 'coordinate_input.dart';

/// Dialog ketik koordinat titik alat ukur (derajat desimal). Menempel
/// "lat, lon" di kolom latitude mengisi kedua kolom. Mengembalikan titik,
/// atau null bila dibatalkan.
Future<LatLng?> showCoordinateDialog(
  BuildContext context, {
  required String title,
  LatLng? initial,
}) {
  return showDialog<LatLng>(
    context: context,
    builder: (context) => _CoordinateDialog(title: title, initial: initial),
  );
}

class _CoordinateDialog extends StatefulWidget {
  final String title;
  final LatLng? initial;

  const _CoordinateDialog({required this.title, this.initial});

  @override
  State<_CoordinateDialog> createState() => _CoordinateDialogState();
}

class _CoordinateDialogState extends State<_CoordinateDialog> {
  late final TextEditingController _lat;
  late final TextEditingController _lon;
  String? _latError;
  String? _lonError;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _lat = TextEditingController(text: p?.latitude.toStringAsFixed(6) ?? '');
    _lon = TextEditingController(text: p?.longitude.toStringAsFixed(6) ?? '');
  }

  @override
  void dispose() {
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  /// Tempel "lat, lon" di kolom latitude → pisahkan ke dua kolom.
  void _onLatChanged(String text) {
    final pair = splitCoordinatePair(text);
    if (pair == null) return;
    _lat.text = pair.$1;
    _lon.text = pair.$2;
  }

  void _save() {
    final r = parseCoordinateInput(_lat.text, _lon.text);
    if (r.point == null) {
      setState(() {
        _latError = r.latError;
        _lonError = r.lonError;
      });
      return;
    }
    Navigator.pop(context, r.point);
  }

  InputDecoration _decoration(String label, String hint, String? error) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: error,
        border: const OutlineInputBorder(),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    const keyboard =
        TextInputType.numberWithOptions(signed: true, decimal: true);
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('coordinateLat'),
            controller: _lat,
            autofocus: true,
            keyboardType: keyboard,
            onChanged: _onLatChanged,
            decoration: _decoration('Latitude', '-6.175392', _latError),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('coordinateLon'),
            controller: _lon,
            keyboardType: keyboard,
            decoration: _decoration('Longitude', '106.827153', _lonError),
          ),
          const SizedBox(height: 8),
          const Text(
            'Decimal degrees. You can paste "lat, lon" into Latitude.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
