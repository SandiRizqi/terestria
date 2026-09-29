import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/geo_data_model.dart';
import '../../services/location_service_v2.dart';

/// Satu banner status (warna, ikon, teks).
@immutable
class GpsBanner {
  final Color color;
  final IconData icon;
  final String text;
  const GpsBanner(this.color, this.icon, this.text);

  @override
  bool operator ==(Object other) =>
      other is GpsBanner && other.text == text && other.color == color;

  @override
  int get hashCode => Object.hash(text, color);
}

/// Banner yang perlu tampil — murni agar mudah diuji. Fokus pada kondisi
/// saat titik TIDAK direkam, yang dulu hanya ditandai ikon 8–10 px.
List<GpsBanner> gpsBannersFor({
  required bool usingEmlid,
  required bool isTracking,
  required bool isPaused,
  required GeoPoint? location,
  required EmlidStatus emlid,
  required Duration? sinceEmlidData,
  required Duration sinceScreenOpen,
  int emlidStaleSeconds = 10,
  double weakAccuracyMeters = 20,
}) {
  const red = Color(0xFFC62828);
  const orange = Color(0xFFEF6C00);
  const blue = Color(0xFF1565C0);
  final banners = <GpsBanner>[];

  if (isTracking && isPaused) {
    banners.add(const GpsBanner(
        blue, Icons.pause_circle, 'Tracking paused — points are not recorded'));
  }

  if (usingEmlid) {
    if (emlid.reconnecting) {
      banners.add(GpsBanner(
          orange,
          Icons.sync,
          'RTK receiver disconnected — reconnecting'
          '${emlid.reconnectAttempt > 0 ? ' (attempt ${emlid.reconnectAttempt})' : ''}…'));
    } else if (!emlid.connected) {
      banners.add(const GpsBanner(orange, Icons.link_off,
          'RTK receiver not connected — open Location Provider'));
    } else if (sinceEmlidData != null &&
        sinceEmlidData.inSeconds > emlidStaleSeconds) {
      banners.add(GpsBanner(orange, Icons.hourglass_bottom,
          'No data from the RTK receiver for ${sinceEmlidData.inSeconds} s'));
    } else if (emlid.belowRequirement) {
      banners.add(GpsBanner(
          red,
          Icons.gps_not_fixed,
          'RTK ${(emlid.lastQuality ?? 'unknown').toUpperCase()} — below the '
          'required ${emlid.requiredQuality.toUpperCase()}; points are not '
          'recorded'));
    }
    return banners;
  }

  if (isTracking && !isPaused) {
    if (location == null) {
      if (sinceScreenOpen.inSeconds > 10) {
        banners.add(const GpsBanner(orange, Icons.gps_not_fixed,
            'Waiting for a GPS fix — move to open sky'));
      }
    } else if (!location.recordable &&
        (location.accuracy ?? 0) > weakAccuracyMeters) {
      banners.add(GpsBanner(
          orange,
          Icons.gps_not_fixed,
          'Weak GPS (±${location.accuracy!.toStringAsFixed(0)} m) — points '
          'are held until accuracy improves'));
    }
  }
  return banners;
}

/// Banner status GPS di layar pengambilan data. Memperbarui diri tiap detik
/// (umur data RTK) tanpa me-rebuild layar peta.
class GpsStatusBanners extends StatefulWidget {
  final ValueListenable<GeoPoint?> location;
  final ValueListenable<EmlidStatus> emlidStatus;
  final bool usingEmlid;
  final bool isTracking;
  final bool isPaused;
  final DateTime? Function() lastEmlidDataTime;
  final int emlidStaleSeconds;

  const GpsStatusBanners({
    super.key,
    required this.location,
    required this.emlidStatus,
    required this.usingEmlid,
    required this.isTracking,
    required this.isPaused,
    required this.lastEmlidDataTime,
    this.emlidStaleSeconds = 10,
  });

  @override
  State<GpsStatusBanners> createState() => _GpsStatusBannersState();
}

class _GpsStatusBannersState extends State<GpsStatusBanners> {
  final DateTime _openedAt = DateTime.now();
  Timer? _ticker;
  List<GpsBanner> _banners = const [];

  @override
  void initState() {
    super.initState();
    widget.location.addListener(_recompute);
    widget.emlidStatus.addListener(_recompute);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _recompute());
    _banners = _compute();
  }

  @override
  void didUpdateWidget(GpsStatusBanners oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      oldWidget.location.removeListener(_recompute);
      widget.location.addListener(_recompute);
    }
    if (oldWidget.emlidStatus != widget.emlidStatus) {
      oldWidget.emlidStatus.removeListener(_recompute);
      widget.emlidStatus.addListener(_recompute);
    }
    _banners = _compute();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    widget.location.removeListener(_recompute);
    widget.emlidStatus.removeListener(_recompute);
    super.dispose();
  }

  List<GpsBanner> _compute() {
    final now = DateTime.now();
    final last = widget.lastEmlidDataTime();
    return gpsBannersFor(
      usingEmlid: widget.usingEmlid,
      isTracking: widget.isTracking,
      isPaused: widget.isPaused,
      location: widget.location.value,
      emlid: widget.emlidStatus.value,
      sinceEmlidData: last == null ? null : now.difference(last),
      sinceScreenOpen: now.difference(_openedAt),
      emlidStaleSeconds: widget.emlidStaleSeconds,
    );
  }

  void _recompute() {
    if (!mounted) return;
    final next = _compute();
    if (listEquals(next, _banners)) return; // hindari rebuild tiap detik
    setState(() => _banners = next);
  }

  @override
  Widget build(BuildContext context) {
    if (_banners.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in _banners)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: b.color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                Icon(b.icon, color: Colors.white, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    b.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
