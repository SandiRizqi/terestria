import 'dart:math' as math;
import 'dart:typed_data';

import 'pbf_reader.dart';

/// Graph jalan routable (CSR / compressed sparse row) untuk mesin routing iOS.
///
/// Edge disimpan TERARAH: tiap ruas OSM jadi dua edge (maju & balik). Flag
/// [edgesFrom]`.car` menandai apakah MOBIL boleh melewati arah itu (oneway).
/// Profil `foot` mengabaikan flag ini (ditangani di A*). Node memakai id dari
/// `.pbf` (sudah ter-dedup by-koordinat oleh roads_osm_builder di server), jadi
/// persimpangan otomatis tersambung lewat id yang sama.
class RoadGraph {
  final Float64List nodeLat; // N
  final Float64List nodeLon; // N
  final Int32List csrOffset; // N+1
  final Int32List edgeTarget; // M (indeks node tujuan)
  final Float64List edgeLength; // M (meter)
  final Float64List edgeSpeed; // M (km/jam, mobil)
  final Uint8List edgeCar; // M (1 = mobil boleh arah ini)
  final Int32List edgeNameId; // M (indeks ke names, -1 = tanpa nama)
  final List<String> names;
  final Map<int, int> _osmIdToIndex;

  RoadGraph._({
    required this.nodeLat,
    required this.nodeLon,
    required this.csrOffset,
    required this.edgeTarget,
    required this.edgeLength,
    required this.edgeSpeed,
    required this.edgeCar,
    required this.edgeNameId,
    required this.names,
    required Map<int, int> osmIdToIndex,
  }) : _osmIdToIndex = osmIdToIndex;

  int get nodeCount => nodeLat.length;
  int get edgeCount => edgeTarget.length;

  int? indexOfOsmId(int osmId) => _osmIdToIndex[osmId];
  double latOf(int node) => nodeLat[node];
  double lonOf(int node) => nodeLon[node];
  String nameOf(int nameId) => nameId >= 0 ? names[nameId] : '';

  /// Edge keluar dari [node] (untuk A*/uji).
  List<({int to, double length, double speed, bool car, String name})>
      edgesFrom(int node) {
    final out = <({int to, double length, double speed, bool car, String name})>[];
    for (var e = csrOffset[node]; e < csrOffset[node + 1]; e++) {
      out.add((
        to: edgeTarget[e],
        length: edgeLength[e],
        speed: edgeSpeed[e],
        car: edgeCar[e] == 1,
        name: nameOf(edgeNameId[e]),
      ));
    }
    return out;
  }
}

class _DirEdge {
  final int to;
  final double length;
  final double speed;
  final bool car;
  final int nameId;
  _DirEdge(this.to, this.length, this.speed, this.car, this.nameId);
}

/// Bangun [RoadGraph] dari hasil [readOsmPbf].
RoadGraph buildGraph(OsmData data) {
  // 1. index node
  final idToIndex = <int, int>{};
  final lat = Float64List(data.nodes.length);
  final lon = Float64List(data.nodes.length);
  for (var i = 0; i < data.nodes.length; i++) {
    final n = data.nodes[i];
    idToIndex[n.id] = i;
    lat[i] = n.lat;
    lon[i] = n.lon;
  }

  // 2. names dedup
  final names = <String>[];
  final nameIndex = <String, int>{};
  int nameIdOf(String? s) {
    if (s == null || s.isEmpty) return -1;
    return nameIndex.putIfAbsent(s, () {
      names.add(s);
      return names.length - 1;
    });
  }

  // 3. edge terarah per node
  final adj = List<List<_DirEdge>>.generate(data.nodes.length, (_) => []);
  for (final w in data.ways) {
    final highway = w.tags['highway'];
    if (highway == null) continue; // hanya jalan
    final speed = _speedFor(highway, w.tags['maxspeed']);
    final oneway = w.tags['oneway'] == 'yes';
    final nameId = nameIdOf(w.tags['name']);

    for (var k = 0; k + 1 < w.refs.length; k++) {
      final ui = idToIndex[w.refs[k]];
      final vi = idToIndex[w.refs[k + 1]];
      if (ui == null || vi == null || ui == vi) continue;
      final len = _haversine(lat[ui], lon[ui], lat[vi], lon[vi]);
      adj[ui].add(_DirEdge(vi, len, speed, true, nameId)); // maju
      adj[vi].add(_DirEdge(ui, len, speed, !oneway, nameId)); // balik
    }
  }

  // 4. ratakan ke CSR
  final n = data.nodes.length;
  final csrOffset = Int32List(n + 1);
  var m = 0;
  for (var i = 0; i < n; i++) {
    csrOffset[i] = m;
    m += adj[i].length;
  }
  csrOffset[n] = m;

  final edgeTarget = Int32List(m);
  final edgeLength = Float64List(m);
  final edgeSpeed = Float64List(m);
  final edgeCar = Uint8List(m);
  final edgeNameId = Int32List(m);
  var e = 0;
  for (var i = 0; i < n; i++) {
    for (final d in adj[i]) {
      edgeTarget[e] = d.to;
      edgeLength[e] = d.length;
      edgeSpeed[e] = d.speed;
      edgeCar[e] = d.car ? 1 : 0;
      edgeNameId[e] = d.nameId;
      e++;
    }
  }

  return RoadGraph._(
    nodeLat: lat,
    nodeLon: lon,
    csrOffset: csrOffset,
    edgeTarget: edgeTarget,
    edgeLength: edgeLength,
    edgeSpeed: edgeSpeed,
    edgeCar: edgeCar,
    edgeNameId: edgeNameId,
    names: names,
    osmIdToIndex: idToIndex,
  );
}

/// Kecepatan (km/jam): maxspeed bila valid, else default per tipe highway.
double _speedFor(String highway, String? maxspeed) {
  if (maxspeed != null) {
    // Ambil angka di depan ("40", "40 km/h", "40 mph" → 40; mph diabaikan konversinya utk MVP)
    final m = RegExp(r'\d+').firstMatch(maxspeed);
    if (m != null) {
      final v = int.tryParse(m.group(0)!);
      if (v != null && v > 0) return v.toDouble();
    }
  }
  return _defaultSpeed[highway] ?? 30.0;
}

const Map<String, double> _defaultSpeed = {
  'motorway': 100,
  'motorway_link': 60,
  'trunk': 80,
  'trunk_link': 50,
  'primary': 65,
  'primary_link': 50,
  'secondary': 60,
  'secondary_link': 50,
  'tertiary': 50,
  'tertiary_link': 40,
  'unclassified': 30,
  'residential': 30,
  'living_street': 10,
  'service': 20,
  'track': 15,
  'road': 30,
  'path': 8,
  'footway': 5,
  'pedestrian': 5,
};

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0; // meter
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180.0;
