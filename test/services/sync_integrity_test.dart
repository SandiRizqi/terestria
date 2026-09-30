import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/geo_data_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/api_service.dart';
import 'package:geoform_app/services/database_service.dart';
import 'package:geoform_app/services/photo_sync_service.dart';
import 'package:geoform_app/services/storage_service.dart';
import 'package:geoform_app/services/sync_service.dart';
import 'package:geoform_app/services/sync_watermark_service.dart';

class _FakeApi implements ApiService {
  final List<http.Response> responses;
  int _i = 0;
  Map<String, dynamic>? lastPostBody;
  _FakeApi(this.responses);

  @override
  Future<http.Response> get(String endpoint,
          {Map<String, String>? headers,
          Map<String, dynamic>? queryParameters}) async =>
      responses[_i++];

  @override
  Future<http.Response> post(String endpoint,
      {Map<String, String>? headers, dynamic body}) async {
    lastPostBody = body as Map<String, dynamic>;
    return responses[_i++];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// Server tiruan untuk pull: menyimpan record dan menerapkan filter
/// `updated_after` PERSIS seperti backend (`updated_at > nilai`, lihat
/// gis-backend `mobile/views.py` by_project). Dulu test memakai daftar respons
/// berurutan yang mengabaikan query — bug watermark lolos karenanya.
class _FakeServer implements ApiService {
  final List<Map<String, dynamic>> records;
  final List<DateTime?> requestedAfter = [];
  _FakeServer(this.records);

  @override
  Future<http.Response> get(String endpoint,
      {Map<String, String>? headers,
      Map<String, dynamic>? queryParameters}) async {
    final query = Uri.parse('http://server$endpoint').queryParameters;
    final after = query['updated_after'] == null
        ? null
        : DateTime.parse(query['updated_after']!);
    requestedAfter.add(after);
    final data = [
      for (final r in records)
        if (after == null ||
            DateTime.parse(r['updated_at'] as String).isAfter(after))
          r,
    ];
    return _page(data);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeStorage implements StorageService {
  final Map<String, GeoData> existing = {};
  final List<GeoData> saved = [];
  final Set<String> failSaveFor = {};
  bool unchanged = true;
  int conditionalSaves = 0;

  @override
  Future<Project?> getProjectById(String projectId) async => _project();

  @override
  Future<GeoData?> getGeoDataById(String id) async => existing[id];

  @override
  Future<void> saveGeoData(GeoData geoData) async {
    if (failSaveFor.contains(geoData.id)) throw Exception('disk full');
    saved.add(geoData);
    existing[geoData.id] = geoData;
  }

  @override
  Future<bool> saveGeoDataIfUnchanged(GeoData geoData,
      {required DateTime expectedUpdatedAt}) async {
    conditionalSaves++;
    if (unchanged) saved.add(geoData);
    return unchanged;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakePhotoSync implements PhotoSyncService {
  @override
  Future<Map<String, dynamic>> processFormDataForPull(
          Map<String, dynamic> formData, Project? project) async =>
      formData;

  @override
  Future<Map<String, dynamic>> processFormDataForPush(
          Map<String, dynamic> formData, Project project) async =>
      formData;

  @override
  List<PendingPhoto> pendingPhotoUploads(
          Map<String, dynamic> formData, Project project) =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Project _project() => Project(
      id: 'p1',
      name: 'Blocks',
      description: '',
      geometryType: GeometryType.point,
      formFields: const [],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      isSynced: true,
    );

GeoData _geo(String id,
        {bool synced = true, DateTime? updatedAt, String? collectedBy}) =>
    GeoData(
      id: id,
      projectId: 'p1',
      formData: const {'Name': 'local'},
      points: [
        GeoPoint(
          latitude: -6.2,
          longitude: 106.8,
          accuracy: 0.02,
          speed: 1.5,
          fixQuality: 'fix',
          satelliteCount: 21,
          timestamp: DateTime.utc(2026, 9, 29, 2, 30),
        )
      ],
      createdAt: DateTime.utc(2026, 9, 29, 2, 30),
      updatedAt: updatedAt ?? DateTime.utc(2026, 9, 29, 2, 31),
      isSynced: synced,
      collectedBy: collectedBy,
    );

Map<String, dynamic> _rec(String id, String updatedAt,
        {Object? altitude = 12.5}) =>
    {
      'id': id,
      'project_id': 'p1',
      'collected_by': null,
      'form_data': <String, dynamic>{'Name': 'server'},
      'points': [
        {
          'latitude': -6, // integer dari server
          'longitude': '106.5', // string (Decimal)
          'altitude': altitude,
          'timestamp': '2026-06-19T11:13:31.843740'
        }
      ],
      'created_at': '2026-06-01T00:00:00+00:00',
      'updated_at': updatedAt,
    };

http.Response _page(List<Map<String, dynamic>> data) =>
    http.Response(jsonEncode({'data': data, 'total_pages': 1}), 200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  SyncService sync(ApiService api, _FakeStorage storage) => SyncService.forTest(
        apiService: api,
        storageService: storage,
        photoSyncService: _FakePhotoSync(),
        watermark: SyncWatermarkService(),
      );

  group('PullWatermarkTracker', () {
    final t1 = DateTime.utc(2026, 6, 1);
    final t2 = DateTime.utc(2026, 6, 2);
    final t3 = DateTime.utc(2026, 6, 3);

    test('semua tuntas → maju ke updatedAt tertinggi', () {
      final t = PullWatermarkTracker()
        ..handled(t1)
        ..handled(t3);
      expect(t.nextWatermark(null), t3);
    });

    test('record gagal menahan watermark tepat SEBELUM waktunya', () {
      final t = PullWatermarkTracker()
        ..handled(t1)
        ..failed(t2)
        ..handled(t3);
      // Server memfilter `updated_at > watermark`: watermark = t2 akan
      // membuang record gagal itu sendiri. −1 µs → record itu ikut lagi.
      expect(t.nextWatermark(null),
          t2.subtract(const Duration(microseconds: 1)));
    });

    test('tahan sebelum record gagal tapi tak pernah mundur', () {
      final t = PullWatermarkTracker()
        ..failed(t1.add(const Duration(microseconds: 1)))
        ..handled(t3);
      expect(t.nextWatermark(t1), t1);
    });

    test('gagal tanpa waktu terbaca → watermark tak bergerak', () {
      final t = PullWatermarkTracker()
        ..handled(t3)
        ..failed(null);
      expect(t.nextWatermark(t1), t1);
    });

    test('tak pernah mundur', () {
      final t = PullWatermarkTracker()..handled(t1);
      expect(t.nextWatermark(t2), t2);
    });
  });

  group('pullGeoDataFromServer', () {
    test('record server dengan collected_by null & angka int/string tersimpan',
        () async {
      final storage = _FakeStorage();
      final api = _FakeApi([
        _page([_rec('g1', '2026-06-21T10:00:00Z', altitude: 0)])
      ]);

      final result = await sync(api, storage).pullGeoDataFromServer('p1');

      expect(result.success, isTrue);
      final g = storage.saved.single;
      expect(g.collectedBy, isNull);
      expect(g.isSynced, isTrue);
      expect(g.points.single.latitude, -6.0);
      expect(g.points.single.longitude, 106.5);
      expect(g.points.single.altitude, 0.0);
    });

    test('edit lokal yang belum sync TIDAK ditimpa versi server', () async {
      final storage = _FakeStorage()
        ..existing['g1'] = _geo('g1',
            synced: false, updatedAt: DateTime.utc(2026, 1, 1));
      final api = _FakeApi([
        _page([_rec('g1', '2026-06-21T10:00:00Z')])
      ]);

      final result = await sync(api, storage).pullGeoDataFromServer('p1');

      expect(result.success, isTrue);
      expect(storage.saved, isEmpty);
      expect(result.data!['conflicts'], 1);
    });

    test('record yang gagal disimpan tidak terlewat oleh watermark', () async {
      final storage = _FakeStorage()..failSaveFor.add('bad');
      final api = _FakeApi([
        _page([
          _rec('ok1', '2026-06-10T00:00:00Z'),
          _rec('bad', '2026-06-15T00:00:00Z'),
          _rec('ok2', '2026-06-20T00:00:00Z'),
        ])
      ]);

      final result = await sync(api, storage).pullGeoDataFromServer('p1');

      expect(result.success, isTrue);
      expect(result.data!['failed'], 1);
      final wm = await SyncWatermarkService().getLastPull('p1');
      expect(
          wm!.isAtSameMomentAs(DateTime.utc(2026, 6, 15)
              .subtract(const Duration(microseconds: 1))),
          isTrue,
          reason: 'watermark must stop just before the failed record');
    });

    test(
        'record yang gagal diambil ulang pada pull berikutnya '
        '(server memfilter updated_at > watermark)', () async {
      final server = _FakeServer([
        _rec('ok1', '2026-06-10T00:00:00Z'),
        _rec('bad', '2026-06-15T00:00:00Z'),
        _rec('ok2', '2026-06-20T00:00:00Z'),
      ]);
      final storage = _FakeStorage()..failSaveFor.add('bad');
      final s = sync(server, storage);

      final first = await s.pullGeoDataFromServer('p1');
      expect(first.data!['failed'], 1);
      expect(storage.existing.keys, isNot(contains('bad')));

      storage.failSaveFor.clear(); // mis. ruang penyimpanan sudah lega
      final second = await s.pullGeoDataFromServer('p1');

      expect(second.data!['failed'], 0);
      expect(storage.existing.keys, contains('bad'),
          reason: 'the failed record must be fetched again');
      expect(server.requestedAfter.last!.isBefore(DateTime.utc(2026, 6, 15)),
          isTrue);
    });
  });

  group('syncGeoData', () {
    test('payload memakai waktu UTC & metadata titik lengkap', () async {
      final storage = _FakeStorage();
      final api = _FakeApi([http.Response('{"message":"ok"}', 201)]);

      final result = await sync(api, storage).syncGeoData(_geo('g1'), _project());

      expect(result.success, isTrue);
      final body = api.lastPostBody!;
      expect(body['created_at'], endsWith('Z'));
      expect(body['updated_at'], endsWith('Z'));
      final p = (body['points'] as List).single as Map;
      expect(p['timestamp'], endsWith('Z'));
      expect(p['fixQuality'], 'fix');
      expect(p['satelliteCount'], 21);
      expect(p['speed'], 1.5);
    });

    test('record diedit selama upload → tidak ditandai synced', () async {
      final storage = _FakeStorage()..unchanged = false;
      final api = _FakeApi([http.Response('{"message":"ok"}', 200)]);

      final result = await sync(api, storage).syncGeoData(_geo('g1'), _project());

      expect(result.success, isTrue); // server menerima snapshot
      expect(storage.conditionalSaves, 1);
      expect(storage.saved, isEmpty, reason: 'local edits must not be overwritten');
    });

    test('2xx bukan JSON (hotspot/proxy) → gagal & dianggap masalah koneksi',
        () async {
      final storage = _FakeStorage();
      final api = _FakeApi([http.Response('<html>login</html>', 200)]);

      final result = await sync(api, storage).syncGeoData(_geo('g1'), _project());

      expect(result.success, isFalse);
      expect(result.isConnectionError, isTrue);
      expect(storage.saved, isEmpty);
    });

    test('401 → isAuthError (bukan pesan mentah)', () async {
      final api = _FakeApi([http.Response('{"detail":"Invalid token."}', 401)]);
      final result =
          await sync(api, _FakeStorage()).syncGeoData(_geo('g1'), _project());
      expect(result.success, isFalse);
      expect(result.isAuthError, isTrue);
    });
  });

  group('parsing', () {
    test('project dari server mempertahankan tipe decimal & defaultValue', () {
      final p = SyncService.parseProjectFromServer({
        'id': 'p9',
        'name': 'Blocks',
        'geometry_type': 'polygon',
        'form_fields': [
          {'id': 'f1', 'label': 'Area', 'type': 'decimal', 'required': true},
          {
            'id': 'f2',
            'label': 'Status',
            'type': 'dropdown',
            'options': ['A', 'B'],
            'defaultValue': 'A'
          },
          {'id': 'f3', 'label': 'Future', 'type': 'signature'},
        ],
        'collectors': ['budi'],
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-02T00:00:00Z',
      });
      expect(p.geometryType, GeometryType.polygon);
      expect(p.formFields[0].type, FieldType.decimal);
      expect(p.formFields[1].defaultValue, 'A');
      expect(p.formFields[2].type, FieldType.text); // tipe baru → aman
      expect(p.collectors, ['budi']);
    });

    test('Project.fromJson geometri tak dikenal tidak melempar', () {
      final p = Project.fromJson({
        'id': 'x',
        'name': 'X',
        'geometryType': 'multipolygon?',
        'formFields': [],
        'createdAt': '2026-01-01T00:00:00Z',
        'updatedAt': '2026-01-01T00:00:00Z',
      });
      expect(p.geometryType, GeometryType.point);
    });

    test('GeoPoint.fromJson: lat rusak → FormatException bernama field', () {
      expect(
          () => GeoPoint.fromJson({
                'latitude': 'abc',
                'longitude': 1,
                'timestamp': '2026-01-01T00:00:00Z'
              }),
          throwsA(isA<FormatException>().having(
              (e) => e.message, 'message', contains('latitude'))));
    });

    test('toJson menulis waktu UTC & bolak-balik tanpa bergeser', () {
      final p = GeoPoint(
          latitude: 1, longitude: 2, timestamp: DateTime(2026, 9, 29, 9));
      final json = p.toJson();
      expect(json['timestamp'], endsWith('Z'));
      final back = GeoPoint.fromJson(json);
      expect(back.timestamp.isAtSameMomentAs(p.timestamp), isTrue);
    });

    test('baris DB: collectedBy null disimpan sebagai string kosong', () {
      final row = DatabaseService.geoDataToRow(_geo('g1', collectedBy: null));
      expect(row['collectedBy'], '');
    });
  });
}
