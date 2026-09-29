import 'package:xml/xml.dart';

import 'layer_importer.dart';
import 'xml_helpers.dart';

/// GPX 1.0/1.1 → GeoJSON FeatureCollection.
///
/// - `wpt` → Point
/// - `trk` → LineString (1 segmen) / MultiLineString (>1 segmen)
/// - `rte` → LineString
///
/// Properti: `name`, `desc`, `ele` (waypoint), `time` (waypoint / titik
/// pertama track), `gpx_type` (`wpt`/`trk`/`rte`). Titik dengan koordinat
/// rusak dan garis <2 titik dilewati.
Map<String, dynamic> gpxToGeoJson(String text) {
  final doc = parseXmlOrThrow(text, 'GPX');
  final root = doc.rootElement;
  final features = <Map<String, dynamic>>[];

  for (final wpt in childrenNamed(root, 'wpt')) {
    final c = _coord(wpt);
    if (c == null) continue;
    features.add(_feature(
      {'type': 'Point', 'coordinates': c},
      {
        ..._meta(wpt),
        if (_ele(wpt) != null) 'ele': _ele(wpt),
        if (childText(wpt, 'time') != null) 'time': childText(wpt, 'time'),
        'gpx_type': 'wpt',
      },
    ));
  }

  for (final trk in childrenNamed(root, 'trk')) {
    final segments = <List<List<double>>>[];
    String? firstTime;
    for (final seg in childrenNamed(trk, 'trkseg')) {
      final pts = childrenNamed(seg, 'trkpt').toList();
      firstTime ??= pts.isEmpty ? null : childText(pts.first, 'time');
      final line = pts.map(_coord).whereType<List<double>>().toList();
      if (line.length >= 2) segments.add(line);
    }
    if (segments.isEmpty) continue;
    features.add(_feature(
      segments.length == 1
          ? {'type': 'LineString', 'coordinates': segments.single}
          : {'type': 'MultiLineString', 'coordinates': segments},
      {
        ..._meta(trk),
        if (firstTime != null) 'time': firstTime,
        'gpx_type': 'trk',
      },
    ));
  }

  for (final rte in childrenNamed(root, 'rte')) {
    final line =
        childrenNamed(rte, 'rtept').map(_coord).whereType<List<double>>().toList();
    if (line.length < 2) continue;
    features.add(_feature(
      {'type': 'LineString', 'coordinates': line},
      {..._meta(rte), 'gpx_type': 'rte'},
    ));
  }

  if (features.isEmpty) {
    throw const LayerImportException(
        'The GPX file has no valid waypoints, tracks or routes');
  }
  return {'type': 'FeatureCollection', 'features': features};
}

Map<String, dynamic> _feature(
        Map<String, dynamic> geometry, Map<String, dynamic> props) =>
    {'type': 'Feature', 'properties': props, 'geometry': geometry};

Map<String, dynamic> _meta(XmlElement e) => {
      if (childText(e, 'name') != null) 'name': childText(e, 'name'),
      if (childText(e, 'desc') != null) 'desc': childText(e, 'desc'),
    };

double? _ele(XmlElement e) => double.tryParse(childText(e, 'ele') ?? '');

/// `[lon, lat]` dari atribut `lat`/`lon`; null bila rusak / di luar rentang.
List<double>? _coord(XmlElement e) {
  final lat = double.tryParse(e.getAttribute('lat') ?? '');
  final lon = double.tryParse(e.getAttribute('lon') ?? '');
  if (lat == null || lon == null) return null;
  if (lat.abs() > 90 || lon.abs() > 180) return null;
  return [lon, lat];
}
