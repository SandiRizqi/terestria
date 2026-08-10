import 'dart:math' show cos, sin, asin, sqrt;
import 'package:latlong2/latlong.dart';

/// Turn sign constants (same values as GraphHopper)
class TurnSign {
  static const int uTurn            = -98;
  static const int keepLeft         = -7;
  static const int turnSharpLeft    = -3;
  static const int turnLeft         = -2;
  static const int turnSlightLeft   = -1;
  static const int continueOnStreet = 0;
  static const int turnSlightRight  = 1;
  static const int turnRight        = 2;
  static const int turnSharpRight   = 3;
  static const int finish           = 4;
  static const int reachedVia       = 5;
  static const int keepRight        = 7;
}

// ─────────────────────────────────────────────────────────────────────────────

class RoutePoint {
  final double latitude;
  final double longitude;

  const RoutePoint(this.latitude, this.longitude);

  LatLng get latLng => LatLng(latitude, longitude);

  @override
  String toString() => 'RoutePoint($latitude, $longitude)';
}

// ─────────────────────────────────────────────────────────────────────────────

class RouteInstruction {
  /// Human-readable turn text from GraphHopper
  final String text;

  /// Distance (meters) from this waypoint to the next instruction
  final double distance;

  /// Time (milliseconds) from this waypoint to the next instruction
  final int time;

  /// GraphHopper turn sign
  final int sign;

  /// Index into route points where this instruction starts
  final int interval;

  const RouteInstruction({
    required this.text,
    required this.distance,
    required this.time,
    required this.sign,
    required this.interval,
  });

  String get formattedDistance {
    if (distance < 1000) return '${distance.toStringAsFixed(0)} m';
    return '${(distance / 1000).toStringAsFixed(1)} km';
  }

  /// Best-effort street/road name extracted from GraphHopper's [text].
  /// e.g. "Turn right onto Jl. Merdeka" → "Jl. Merdeka",
  ///      "Belok kanan ke Jalan Sudirman" → "Jalan Sudirman".
  /// Returns '' when no road name is present (e.g. roundabouts, finish).
  String get streetName {
    final t = text.trim();
    if (t.isEmpty) return '';
    // Connector words that precede a road name across GraphHopper locales.
    final markers = [' onto ', ' on ', ' ke ', ' menuju ', ' di ', ' pada '];
    for (final m in markers) {
      final idx = t.toLowerCase().indexOf(m);
      if (idx != -1) {
        final name = t.substring(idx + m.length).trim();
        // Only accept the cut when it looks like a road name — connectors
        // also appear before directions/targets ("Tiba di tujuan",
        // "Belok kanan ke arah selatan"), which are not street names.
        if (name.isNotEmpty && !_isNonStreetWord(name)) return name;
      }
    }
    // If the text doesn't merely restate the maneuver, surface it as-is.
    final startsGeneric = _genericManeuverWords
        .any((g) => t.toLowerCase().startsWith(g));
    return startsGeneric ? '' : t;
  }

  static const _genericManeuverWords = [
    'turn', 'continue', 'keep', 'arrive', 'depart', 'head',
    'belok', 'lurus', 'lanjut', 'tiba', 'jaga', 'putar', 'sedikit',
  ];

  /// Words that follow a connector but are NOT street names: directions,
  /// destinations, roundabout phrasing (EN + ID GraphHopper locales).
  static const _nonStreetWords = [
    'tujuan', 'kiri', 'kanan', 'arah', 'bundaran',
    'utara', 'selatan', 'timur', 'barat',
    'destination', 'left', 'right', 'roundabout',
    'north', 'south', 'east', 'west',
  ];

  static bool _isNonStreetWord(String name) {
    final first = name.toLowerCase().split(RegExp(r'\s+')).first;
    return _nonStreetWords.contains(first);
  }

  /// Localized direction label mapped from sign
  String get directionLabel {
    switch (sign) {
      case TurnSign.uTurn:             return 'Putar Balik';
      case TurnSign.keepLeft:          return 'Jaga Kiri';
      case TurnSign.turnSharpLeft:     return 'Belok Tajam Kiri';
      case TurnSign.turnLeft:          return 'Belok Kiri';
      case TurnSign.turnSlightLeft:    return 'Sedikit ke Kiri';
      case TurnSign.continueOnStreet:  return 'Lurus';
      case TurnSign.turnSlightRight:   return 'Sedikit ke Kanan';
      case TurnSign.turnRight:         return 'Belok Kanan';
      case TurnSign.turnSharpRight:    return 'Belok Tajam Kanan';
      case TurnSign.finish:            return 'Tiba di Tujuan';
      case TurnSign.reachedVia:        return 'Melewati Waypoint';
      case TurnSign.keepRight:         return 'Jaga Kanan';
      default:                         return text.isNotEmpty ? text : 'Lanjutkan';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class SnappedResult {
  /// The snapped position on the route
  final LatLng point;

  /// Index of the route segment where the snap occurred
  final int segmentIndex;

  /// Perpendicular distance from GPS position to route (meters)
  final double distanceToRoute;

  /// True when distanceToRoute exceeds off-route threshold
  final bool isOffRoute;

  const SnappedResult({
    required this.point,
    required this.segmentIndex,
    required this.distanceToRoute,
    required this.isOffRoute,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

class RouteResult {
  final List<RoutePoint> points;
  final List<RouteInstruction> instructions;

  /// Total distance (meters)
  final double distance;

  /// Total time (milliseconds)
  final int time;

  final double ascend;
  final double descend;

  const RouteResult({
    required this.points,
    required this.instructions,
    required this.distance,
    required this.time,
    this.ascend = 0,
    this.descend = 0,
  });

  factory RouteResult.fromMap(Map<dynamic, dynamic> map) {
    final rawPoints = (map['points'] as List).cast<Map>();
    final rawInstrs = (map['instructions'] as List).cast<Map>();

    return RouteResult(
      points: rawPoints
          .map((p) => RoutePoint(
                (p['lat'] as num).toDouble(),
                (p['lon'] as num).toDouble(),
              ))
          .toList(),
      instructions: rawInstrs
          .map((i) => RouteInstruction(
                text:     (i['text'] as String?) ?? '',
                distance: (i['distance'] as num).toDouble(),
                time:     (i['time'] as num).toInt(),
                sign:     (i['sign'] as num).toInt(),
                interval: (i['interval'] as num?)?.toInt() ?? 0,
              ))
          .toList(),
      distance: (map['distance'] as num).toDouble(),
      time:     (map['time'] as num).toInt(),
      ascend:   (map['ascend']  as num?)?.toDouble() ?? 0,
      descend:  (map['descend'] as num?)?.toDouble() ?? 0,
    );
  }

  List<LatLng> get latLngs => points.map((p) => p.latLng).toList();

  String get formattedDistance {
    if (distance < 1000) return '${distance.toStringAsFixed(0)} m';
    return '${(distance / 1000).toStringAsFixed(1)} km';
  }

  String get formattedTime {
    final minutes = time ~/ 60000;
    if (minutes < 60) return '$minutes menit';
    return '${minutes ~/ 60}j ${minutes % 60}m';
  }

  /// Remaining distance from a given point index (meters)
  double remainingDistance(int fromIndex) {
    if (fromIndex >= points.length - 1) return 0;
    double dist = 0;
    for (int i = fromIndex; i < points.length - 1; i++) {
      dist += _haversineMeters(
        points[i].latitude,     points[i].longitude,
        points[i + 1].latitude, points[i + 1].longitude,
      );
    }
    return dist;
  }

  static double _haversineMeters(
      double lat1, double lon1, double lat2, double lon2) {
    const r     = 6371000.0;
    const toRad = 3.141592653589793 / 180;
    final dLat  = (lat2 - lat1) * toRad;
    final dLon  = (lon2 - lon1) * toRad;
    final sinLat = sin(dLat / 2);
    final sinLon = sin(dLon / 2);
    final a     = sinLat * sinLat +
        cos(lat1 * toRad) * cos(lat2 * toRad) *
            sinLon * sinLon;
    return r * 2 * asin(sqrt(a.clamp(0.0, 1.0)));
  }
}
