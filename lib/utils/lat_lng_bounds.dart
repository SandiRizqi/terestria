import 'package:latlong2/latlong.dart';

/// Helper class untuk menentukan bounds dari koordinat latitude dan longitude
class LatLngBounds {
  final LatLng northWest;
  final LatLng southEast;

  LatLngBounds({
    required this.northWest,
    required this.southEast,
  });

  /// Create bounds from two corners
  factory LatLngBounds.fromCorners(LatLng corner1, LatLng corner2) {
    final north = corner1.latitude > corner2.latitude ? corner1.latitude : corner2.latitude;
    final south = corner1.latitude < corner2.latitude ? corner1.latitude : corner2.latitude;
    final west = corner1.longitude < corner2.longitude ? corner1.longitude : corner2.longitude;
    final east = corner1.longitude > corner2.longitude ? corner1.longitude : corner2.longitude;

    return LatLngBounds(
      northWest: LatLng(north, west),
      southEast: LatLng(south, east),
    );
  }

  /// Create bounds from list of points
  factory LatLngBounds.fromPoints(List<LatLng> points) {
    if (points.isEmpty) {
      throw ArgumentError('Cannot create bounds from empty list');
    }

    double? north;
    double? south;
    double? east;
    double? west;

    for (final point in points) {
      north = north == null ? point.latitude : (point.latitude > north ? point.latitude : north);
      south = south == null ? point.latitude : (point.latitude < south ? point.latitude : south);
      east = east == null ? point.longitude : (point.longitude > east ? point.longitude : east);
      west = west == null ? point.longitude : (point.longitude < west ? point.longitude : west);
    }

    return LatLngBounds(
      northWest: LatLng(north!, west!),
      southEast: LatLng(south!, east!),
    );
  }

  /// Get the north latitude
  double get north => northWest.latitude;

  /// Get the south latitude
  double get south => southEast.latitude;

  /// Get the west longitude
  double get west => northWest.longitude;

  /// Get the east longitude
  double get east => southEast.longitude;

  /// Get center point
  LatLng get center {
    return LatLng(
      (north + south) / 2,
      (east + west) / 2,
    );
  }

  /// Check if a point is within bounds
  bool contains(LatLng point) {
    return point.latitude >= south &&
        point.latitude <= north &&
        point.longitude >= west &&
        point.longitude <= east;
  }

  /// Expand bounds to include a point
  LatLngBounds extend(LatLng point) {
    return LatLngBounds(
      northWest: LatLng(
        point.latitude > north ? point.latitude : north,
        point.longitude < west ? point.longitude : west,
      ),
      southEast: LatLng(
        point.latitude < south ? point.latitude : south,
        point.longitude > east ? point.longitude : east,
      ),
    );
  }

  /// Pad the bounds by a percentage (0.1 = 10%)
  LatLngBounds pad(double bufferRatio) {
    final heightBuffer = (north - south) * bufferRatio;
    final widthBuffer = (east - west) * bufferRatio;

    return LatLngBounds(
      northWest: LatLng(north + heightBuffer, west - widthBuffer),
      southEast: LatLng(south - heightBuffer, east + widthBuffer),
    );
  }

  @override
  String toString() {
    return 'LatLngBounds(NW: $northWest, SE: $southEast)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LatLngBounds &&
        other.northWest == northWest &&
        other.southEast == southEast;
  }

  @override
  int get hashCode => northWest.hashCode ^ southEast.hashCode;
}
