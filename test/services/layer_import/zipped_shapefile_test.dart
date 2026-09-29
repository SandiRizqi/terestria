import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/layer_import/layer_importer.dart';
import 'package:geoform_app/services/layer_import/prj_projection.dart';
import 'package:geoform_app/services/layer_import/zipped_shapefile.dart';

import 'shapefile_fixtures.dart';

const _esriUtm48S = 'PROJCS["WGS_1984_UTM_Zone_48S",GEOGCS["GCS_WGS_1984",'
    'DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],'
    'PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],'
    'PROJECTION["Transverse_Mercator"],PARAMETER["False_Easting",500000.0],'
    'PARAMETER["False_Northing",10000000.0],PARAMETER["Central_Meridian",105.0],'
    'PARAMETER["Scale_Factor",0.9996],PARAMETER["Latitude_Of_Origin",0.0],'
    'UNIT["Meter",1.0]]';

const _ogcUtm51N = 'PROJCS["WGS 84 / UTM zone 51N",GEOGCS["WGS 84",'
    'DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,'
    'AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],'
    'PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],'
    'UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],'
    'AUTHORITY["EPSG","4326"]],PROJECTION["Transverse_Mercator"],'
    'PARAMETER["latitude_of_origin",0],PARAMETER["central_meridian",123],'
    'PARAMETER["scale_factor",0.9996],PARAMETER["false_easting",500000],'
    'PARAMETER["false_northing",0],UNIT["metre",1,AUTHORITY["EPSG","9001"]],'
    'AXIS["Easting",EAST],AXIS["Northing",NORTH],AUTHORITY["EPSG","32651"]]';

const _geogWgs84 = 'GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",'
    'SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],'
    'UNIT["Degree",0.0174532925199433]]';

const _dgn95Tm3 = 'PROJCS["DGN95 / Indonesia TM-3 zone 49.1",GEOGCS["DGN95",'
    'DATUM["Datum_Geodesi_Nasional_1995",SPHEROID["WGS 84",6378137,'
    '298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]],'
    'PROJECTION["Transverse_Mercator"],PARAMETER["latitude_of_origin",0],'
    'PARAMETER["central_meridian",109.5],PARAMETER["scale_factor",0.9999],'
    'PARAMETER["false_easting",200000],PARAMETER["false_northing",1500000],'
    'UNIT["metre",1]]';

const _batavia = 'PROJCS["Batavia / UTM zone 48S",GEOGCS["Batavia",'
    'DATUM["Batavia",SPHEROID["Bessel 1841",6377397.155,299.1528128]],'
    'PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]],'
    'PROJECTION["Transverse_Mercator"],PARAMETER["latitude_of_origin",0],'
    'PARAMETER["central_meridian",105],PARAMETER["scale_factor",0.9996],'
    'PARAMETER["false_easting",500000],PARAMETER["false_northing",10000000],'
    'UNIT["metre",1]]';

const _lcc = 'PROJCS["WGS 84 / Lambert",GEOGCS["WGS 84",DATUM["WGS_1984",'
    'SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],'
    'UNIT["degree",0.0174532925199433]],'
    'PROJECTION["Lambert_Conformal_Conic_2SP"],UNIT["metre",1]]';

const _utmBbox = [600000.0, 9200000.0, 700000.0, 9300000.0];
const _degBbox = [106.0, -7.0, 107.0, -6.0];

Matcher _lonLat(double lon, double lat) => predicate<List<double>>(
    (p) => (p[0] - lon).abs() < 1e-7 && (p[1] - lat).abs() < 1e-7,
    '≈ [$lon, $lat]');

Uint8List _zip(Map<String, List<int>> files) {
  final a = Archive();
  files.forEach((name, bytes) => a.addFile(ArchiveFile(name, bytes.length, bytes)));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

final _dbf1 = buildDbf(const [DbfField('BLOK', 'C', 6)], [
  ['A1'],
]);

void main() {
  group('Transverse Mercator (acuan proj4dart, selisih < 1 cm)', () {
    test('UTM zona 48S/49S/50S/51N: inverse & forward', () {
      final cases = [
        (48, true, 106.8, -6.2, 699163.391, 9314348.962),
        (49, true, 110.4, -7.0, 433728.200, 9226208.845),
        (50, true, 117.1, -1.2, 511125.078, 9867363.547),
        (51, false, 125.0, 1.5, 722519.610, 165897.144),
      ];
      for (final (zone, south, lon, lat, e, n) in cases) {
        final tm = utmZone(zone, south: south);
        expect(tm.inverse(e, n), _lonLat(lon, lat), reason: 'zona $zone');
        final f = tm.forward(lon, lat);
        expect(f[0], closeTo(e, 0.01));
        expect(f[1], closeTo(n, 0.01));
      }
    });
  });

  group('transformFromPrj', () {
    test('UTM WGS84 WKT ESRI & OGC → lon/lat', () {
      expect(transformFromPrj(_esriUtm48S, bbox: _utmBbox)!(699163.391, 9314348.962),
          _lonLat(106.8, -6.2));
      expect(transformFromPrj(_ogcUtm51N, bbox: _utmBbox)!(722519.610, 165897.144),
          _lonLat(125.0, 1.5));
    });

    test('TM-3 DGN95 (datum setara WGS84) ikut didukung', () {
      expect(transformFromPrj(_dgn95Tm3, bbox: _utmBbox)!(277290.350, 692784.795),
          _lonLat(110.2, -7.3));
    });

    test('geografis WGS84 / tanpa .prj berkoordinat derajat → apa adanya', () {
      expect(transformFromPrj(_geogWgs84, bbox: _degBbox), isNull);
      expect(transformFromPrj(null, bbox: _degBbox), isNull);
      expect(transformFromPrj('  ', bbox: _degBbox), isNull);
    });

    test('ditolak dengan pesan: datum lain, proyeksi lain, tanpa .prj & '
        'bukan derajat', () {
      expect(
          () => transformFromPrj(_batavia, bbox: _utmBbox),
          throwsA(isA<LayerImportException>().having(
              (e) => e.message, 'message', contains('Batavia / UTM zone 48S'))));
      expect(() => transformFromPrj(_lcc, bbox: _utmBbox),
          throwsA(isA<LayerImportException>()));
      expect(
          () => transformFromPrj(null, bbox: _utmBbox),
          throwsA(isA<LayerImportException>()
              .having((e) => e.message, 'message', contains('.prj'))));
    });
  });

  group('zippedShapefileToGeoJson', () {
    test('zip UTM 48S lengkap (+folder, +.cpg) → koordinat WGS84 + atribut',
        () {
      final zip = _zip({
        'kebun/blok.shp': buildShp(1, [pointRecord(699163.391, 9314348.962)]),
        'kebun/blok.shx': [0],
        'kebun/blok.dbf': _dbf1,
        'kebun/blok.prj': utf8.encode(_esriUtm48S),
        'kebun/blok.cpg': utf8.encode('UTF-8'),
      });
      final f = (zippedShapefileToGeoJson(zip)['features'] as List).single;
      expect((f['geometry']['coordinates'] as List).cast<double>(),
          _lonLat(106.8, -6.2));
      expect(f['properties'], {'BLOK': 'A1'});
    });

    test('ekstensi huruf besar & sampah macOS diabaikan', () {
      final zip = _zip({
        'BLOK.SHP': buildShp(1, [pointRecord(106.8, -6.2)]),
        'BLOK.DBF': _dbf1,
        '__MACOSX/._BLOK.SHP': [1, 2, 3],
      });
      expect(zippedShapefileToGeoJson(zip)['features'], hasLength(1));
    });

    test('tanpa .dbf / tanpa .shp / bukan zip → pesan jelas', () {
      expect(
          () => zippedShapefileToGeoJson(
              _zip({'a.shp': buildShp(1, [pointRecord(1, 1)])})),
          throwsA(isA<LayerImportException>()
              .having((e) => e.message, 'message', contains('.dbf'))));
      expect(() => zippedShapefileToGeoJson(_zip({'a.txt': [65]})),
          throwsA(isA<LayerImportException>()
              .having((e) => e.message, 'message', contains('.shp'))));
      expect(() => zippedShapefileToGeoJson(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<LayerImportException>()));
    });

    test('>1 shapefile → MultipleShapefilesException berisi nama; pilih satu',
        () {
      final zip = _zip({
        'jalan.shp': buildShp(1, [pointRecord(1, 1)]),
        'jalan.dbf': _dbf1,
        'blok.shp': buildShp(1, [pointRecord(2, 2), pointRecord(3, 3)]),
        'blok.dbf': buildDbf(const [DbfField('X', 'C', 1)], [
          ['a'],
          ['b'],
        ]),
      });
      expect(
          () => zippedShapefileToGeoJson(zip),
          throwsA(isA<MultipleShapefilesException>()
              .having((e) => e.names, 'names', ['blok', 'jalan'])));
      expect(zippedShapefileToGeoJson(zip, shapefileName: 'blok')['features'],
          hasLength(2));
    });

    test('proyeksi hasil di luar lon/lat (prj salah) → ditolak', () {
      final zip = _zip({
        'a.shp': buildShp(1, [pointRecord(699163.391, 9314348.962)]),
        'a.dbf': _dbf1,
        'a.prj': utf8.encode(_geogWgs84), // bohong: sebenarnya UTM
      });
      expect(() => zippedShapefileToGeoJson(zip),
          throwsA(isA<LayerImportException>()
              .having((e) => e.message, 'message', contains('.prj'))));
    });
  });

  group('importLayerFile (.zip) lewat isolate', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('shpzip'));
    tearDown(() => dir.delete(recursive: true));

    test('hasil GeoJSON + nama default dari nama zip', () async {
      final f = File('${dir.path}/Blok Kebun.zip')
        ..writeAsBytesSync(_zip({
          'blok.shp': buildShp(1, [pointRecord(699163.391, 9314348.962)]),
          'blok.dbf': _dbf1,
          'blok.prj': utf8.encode(_esriUtm48S),
        }));
      final r = await importLayerFile(f.path, fileName: 'Blok Kebun.zip');
      expect(r.format, LayerFormat.zippedShapefile);
      expect(r.defaultName, 'Blok Kebun');
      expect(r.geometryType, 'Point');
      expect(r.propertyKeys, ['BLOK']);
    });

    test('tipe exception (termasuk daftar shapefile) selamat melewati isolate',
        () async {
      final f = File('${dir.path}/dua.zip')
        ..writeAsBytesSync(_zip({
          'a.shp': buildShp(1, [pointRecord(1, 1)]),
          'a.dbf': _dbf1,
          'b.shp': buildShp(1, [pointRecord(2, 2)]),
          'b.dbf': _dbf1,
        }));
      await expectLater(
          importLayerFile(f.path, fileName: 'dua.zip'),
          throwsA(isA<MultipleShapefilesException>()
              .having((e) => e.names, 'names', ['a', 'b'])));
      final r = await importLayerFile(f.path,
          fileName: 'dua.zip', shapefileName: 'b');
      expect(r.featureCount, 1);
    });
  });
}
