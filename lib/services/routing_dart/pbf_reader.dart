import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Pembaca `.osm.pbf` MINIMAL untuk mesin routing Dart (iOS).
///
/// Hanya menangani yang dibutuhkan mesin routing dan yang ditulis
/// `roads_osm_builder.write_pbf` (pyosmium): OSMData → PrimitiveBlock →
/// DenseNodes + Way. Tanpa relation, tanpa metadata. Terpisah dari kode
/// existing; tidak dipakai di jalur Android.
///
/// Format PBF: rangkaian blob = [int32 BE panjang BlobHeader][BlobHeader]
/// [Blob(datasize)]. Blob berisi `raw` atau `zlib_data` (di-inflate) →
/// HeaderBlock (dilewati) atau PrimitiveBlock.
class OsmNode {
  final int id;
  final double lat;
  final double lon;
  const OsmNode(this.id, this.lat, this.lon);
}

class OsmWay {
  final int id;
  final List<int> refs;
  final Map<String, String> tags;
  const OsmWay(this.id, this.refs, this.tags);
}

class OsmData {
  final List<OsmNode> nodes;
  final List<OsmWay> ways;
  const OsmData(this.nodes, this.ways);
}

class OsmPbfException implements Exception {
  final String message;
  OsmPbfException(this.message);
  @override
  String toString() => 'OsmPbfException: $message';
}

/// Parse seluruh isi `.osm.pbf`. Melempar [OsmPbfException] bila struktur rusak.
OsmData readOsmPbf(Uint8List bytes) {
  final nodes = <OsmNode>[];
  final ways = <OsmWay>[];
  var pos = 0;
  try {
    while (pos < bytes.length) {
      if (pos + 4 > bytes.length) {
        throw OsmPbfException('truncated blob header length at $pos');
      }
      final headerLen = (bytes[pos] << 24) |
          (bytes[pos + 1] << 16) |
          (bytes[pos + 2] << 8) |
          bytes[pos + 3];
      pos += 4;
      if (headerLen <= 0 || pos + headerLen > bytes.length) {
        throw OsmPbfException('invalid BlobHeader length $headerLen');
      }
      final header = _parseBlobHeader(bytes, pos, pos + headerLen);
      pos += headerLen;

      final blobEnd = pos + header.dataSize;
      if (header.dataSize < 0 || blobEnd > bytes.length) {
        throw OsmPbfException('invalid Blob datasize ${header.dataSize}');
      }
      final blob = _inflateBlob(bytes, pos, blobEnd);
      pos = blobEnd;

      if (header.type == 'OSMData') {
        _parsePrimitiveBlock(blob, nodes, ways);
      }
      // 'OSMHeader' & lainnya: dilewati.
    }
  } on OsmPbfException {
    rethrow;
  } catch (e) {
    throw OsmPbfException('parse error: $e');
  }
  return OsmData(nodes, ways);
}

// ─── Blob header & dekompresi ────────────────────────────────────────────────

class _BlobHeader {
  final String type;
  final int dataSize;
  _BlobHeader(this.type, this.dataSize);
}

_BlobHeader _parseBlobHeader(Uint8List b, int start, int end) {
  final r = _Proto(b, start, end);
  String type = '';
  int dataSize = 0;
  while (r.hasMore) {
    final tag = r.readVarint();
    switch (tag >> 3) {
      case 1: // type (string)
        type = utf8.decode(r.readLengthDelimited());
        break;
      case 3: // datasize (int32)
        dataSize = r.readVarint();
        break;
      default:
        r.skip(tag & 7);
    }
  }
  return _BlobHeader(type, dataSize);
}

/// Blob: field 1 = raw (tanpa kompresi), field 3 = zlib_data (di-inflate).
Uint8List _inflateBlob(Uint8List b, int start, int end) {
  final r = _Proto(b, start, end);
  while (r.hasMore) {
    final tag = r.readVarint();
    switch (tag >> 3) {
      case 1: // raw
        return Uint8List.fromList(r.readLengthDelimited());
      case 3: // zlib_data
        final z = r.readLengthDelimited();
        return Uint8List.fromList(const ZLibDecoder().decodeBytes(z));
      default:
        r.skip(tag & 7);
    }
  }
  throw OsmPbfException('Blob tanpa raw/zlib_data');
}

// ─── PrimitiveBlock ──────────────────────────────────────────────────────────

void _parsePrimitiveBlock(
    Uint8List b, List<OsmNode> nodes, List<OsmWay> ways) {
  final r = _Proto(b, 0, b.length);
  List<String> strings = const [];
  final groupRanges = <List<int>>[]; // [start,end]
  int granularity = 100;
  int latOffset = 0;
  int lonOffset = 0;

  while (r.hasMore) {
    final tag = r.readVarint();
    switch (tag >> 3) {
      case 1: // stringtable
        strings = _parseStringTable(b, r.readLengthDelimitedRange());
        break;
      case 2: // primitivegroup (bisa banyak)
        groupRanges.add(r.readLengthDelimitedRange());
        break;
      case 17: // granularity
        granularity = r.readVarint();
        break;
      case 19: // lat_offset (int64)
        latOffset = r.readVarint();
        break;
      case 20: // lon_offset (int64)
        lonOffset = r.readVarint();
        break;
      default:
        r.skip(tag & 7);
    }
  }

  for (final range in groupRanges) {
    _parseGroup(b, range[0], range[1], strings, granularity, latOffset,
        lonOffset, nodes, ways);
  }
}

/// StringTable: field 1 = repeated bytes `s`. Index 0 biasanya string kosong.
List<String> _parseStringTable(Uint8List b, List<int> range) {
  final r = _Proto(b, range[0], range[1]);
  final out = <String>[];
  while (r.hasMore) {
    final tag = r.readVarint();
    if (tag >> 3 == 1) {
      out.add(utf8.decode(r.readLengthDelimited(), allowMalformed: true));
    } else {
      r.skip(tag & 7);
    }
  }
  return out;
}

void _parseGroup(Uint8List b, int start, int end, List<String> strings,
    int granularity, int latOffset, int lonOffset,
    List<OsmNode> nodes, List<OsmWay> ways) {
  final r = _Proto(b, start, end);
  while (r.hasMore) {
    final tag = r.readVarint();
    switch (tag >> 3) {
      case 1: // nodes (non-dense) — repeated Node
        _parseNode(b, r.readLengthDelimitedRange(), granularity, latOffset,
            lonOffset, nodes);
        break;
      case 2: // dense
        _parseDense(b, r.readLengthDelimitedRange(), granularity, latOffset,
            lonOffset, nodes);
        break;
      case 3: // ways
        _parseWay(b, r.readLengthDelimitedRange(), strings, ways);
        break;
      default:
        r.skip(tag & 7);
    }
  }
}

void _parseNode(Uint8List b, List<int> range, int granularity, int latOffset,
    int lonOffset, List<OsmNode> nodes) {
  final r = _Proto(b, range[0], range[1]);
  int id = 0, lat = 0, lon = 0;
  while (r.hasMore) {
    final tag = r.readVarint();
    switch (tag >> 3) {
      case 1:
        id = _zigzag(r.readVarint());
        break;
      case 8:
        lat = _zigzag(r.readVarint());
        break;
      case 9:
        lon = _zigzag(r.readVarint());
        break;
      default:
        r.skip(tag & 7);
    }
  }
  nodes.add(OsmNode(id, _coord(latOffset, granularity, lat),
      _coord(lonOffset, granularity, lon)));
}

void _parseDense(Uint8List b, List<int> range, int granularity, int latOffset,
    int lonOffset, List<OsmNode> nodes) {
  final r = _Proto(b, range[0], range[1]);
  List<int> ids = const [], lats = const [], lons = const [];
  while (r.hasMore) {
    final tag = r.readVarint();
    switch (tag >> 3) {
      case 1: // id (packed sint64 delta)
        ids = r.readPackedVarints();
        break;
      case 8: // lat (packed sint64 delta)
        lats = r.readPackedVarints();
        break;
      case 9: // lon (packed sint64 delta)
        lons = r.readPackedVarints();
        break;
      default:
        // field 10 keys_vals & lainnya: tak dibutuhkan (node routing tanpa tag)
        r.skip(tag & 7);
    }
  }
  int id = 0, lat = 0, lon = 0;
  final n = ids.length;
  for (var i = 0; i < n; i++) {
    id += _zigzag(ids[i]);
    lat += _zigzag(lats[i]);
    lon += _zigzag(lons[i]);
    nodes.add(OsmNode(id, _coord(latOffset, granularity, lat),
        _coord(lonOffset, granularity, lon)));
  }
}

void _parseWay(
    Uint8List b, List<int> range, List<String> strings, List<OsmWay> ways) {
  final r = _Proto(b, range[0], range[1]);
  int id = 0;
  List<int> keys = const [], vals = const [], refsRaw = const [];
  while (r.hasMore) {
    final tag = r.readVarint();
    switch (tag >> 3) {
      case 1: // id
        id = r.readVarint();
        break;
      case 2: // keys (packed uint32)
        keys = r.readPackedVarints();
        break;
      case 3: // vals (packed uint32)
        vals = r.readPackedVarints();
        break;
      case 8: // refs (packed sint64 delta)
        refsRaw = r.readPackedVarints();
        break;
      default:
        r.skip(tag & 7);
    }
  }
  // refs: delta-decoded
  final refs = <int>[];
  int ref = 0;
  for (final d in refsRaw) {
    ref += _zigzag(d);
    refs.add(ref);
  }
  // tags: zip(keys, vals) → stringtable
  final tags = <String, String>{};
  final m = keys.length < vals.length ? keys.length : vals.length;
  for (var i = 0; i < m; i++) {
    final k = keys[i], v = vals[i];
    if (k < strings.length && v < strings.length) {
      tags[strings[k]] = strings[v];
    }
  }
  ways.add(OsmWay(id, refs, tags));
}

double _coord(int offset, int granularity, int delta) =>
    1e-9 * (offset + granularity * delta);

int _zigzag(int n) => (n >>> 1) ^ -(n & 1);

// ─── Decoder protobuf wire-format (minimal) ──────────────────────────────────

class _Proto {
  final Uint8List b;
  int pos;
  final int end;
  _Proto(this.b, this.pos, this.end);

  bool get hasMore => pos < end;

  int readVarint() {
    var shift = 0;
    var result = 0;
    while (true) {
      if (pos >= end) throw OsmPbfException('varint melewati batas');
      final byte = b[pos++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) break;
      shift += 7;
    }
    return result;
  }

  /// Kembalikan [start,end] untuk field length-delimited tanpa menyalin.
  List<int> readLengthDelimitedRange() {
    final len = readVarint();
    final s = pos;
    final e = pos + len;
    if (e > end) throw OsmPbfException('length-delimited melewati batas');
    pos = e;
    return [s, e];
  }

  List<int> readLengthDelimited() {
    final r = readLengthDelimitedRange();
    return b.sublist(r[0], r[1]);
  }

  /// Packed repeated varint (untuk id/lat/lon/keys/vals/refs).
  List<int> readPackedVarints() {
    final r = readLengthDelimitedRange();
    final sub = _Proto(b, r[0], r[1]);
    final out = <int>[];
    while (sub.hasMore) {
      out.add(sub.readVarint());
    }
    return out;
  }

  void skip(int wireType) {
    switch (wireType) {
      case 0:
        readVarint();
        break;
      case 1:
        pos += 8;
        break;
      case 2:
        final len = readVarint();
        pos += len;
        break;
      case 5:
        pos += 4;
        break;
      default:
        throw OsmPbfException('wire type tak didukung: $wireType');
    }
    if (pos > end) throw OsmPbfException('skip melewati batas');
  }
}
