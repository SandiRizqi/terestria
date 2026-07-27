import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/form_field_model.dart';
import 'package:geoform_app/models/project_model.dart';
import 'package:geoform_app/services/api_service.dart';
import 'package:geoform_app/services/photo_sync_service.dart';

/// Fake upload endpoint that tracks concurrency and can fail selected files.
class _FakeApi implements ApiService {
  int inFlight = 0;
  int maxInFlight = 0;
  int calls = 0;
  final Set<String> failFor;

  _FakeApi({this.failFor = const {}});

  @override
  Future<Map<String, dynamic>?> uploadFile(
    String url,
    dynamic file, {
    String fileFieldName = 'file',
    Map<String, String>? fields,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    calls++;
    inFlight++;
    maxInFlight = max(maxInFlight, inFlight);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    inFlight--;

    final path = file is File ? file.path : file.toString();
    final name = path.split('/').last;
    if (failFor.contains(name)) return null;
    return {'success': true, 'file_url': 'https://oss/$name', 'key': 'Production/$name'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Project _project() => Project(
      id: 'p1',
      name: 't',
      description: '',
      geometryType: GeometryType.point,
      formFields: [
        FormFieldModel(id: 'f1', label: 'Photo', type: FieldType.photo),
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Map<String, dynamic> _photo(String localPath) => {
      'name': localPath.split('/').last,
      'localPath': localPath,
      'serverKey': null,
      'serverUrl': null,
      'created': DateTime(2026, 1, 1).toIso8601String(),
      'updated': DateTime(2026, 1, 1).toIso8601String(),
    };

void main() {
  late Directory dir;
  late List<File> files;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('concurrency');
    files = List.generate(
      4,
      (i) => File('${dir.path}/p$i.jpg')..writeAsBytesSync([i]),
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test('uploads in parallel (bounded to 3) and preserves order on partial failure',
      () async {
    final api = _FakeApi(failFor: {'p2.jpg'}); // p2 fails to upload
    final service = PhotoSyncService.forTest(apiService: api);
    final formData = {'Photo': files.map((f) => _photo(f.path)).toList()};

    final result = await service.processFormDataForPush(formData, _project());

    final photos = (result['Photo'] as List).cast<Map>();
    expect(photos, hasLength(4));

    // Order preserved: position i still maps to p$i.jpg.
    for (var i = 0; i < 4; i++) {
      expect(photos[i]['name'], 'p$i.jpg');
    }

    // Successful uploads got a serverKey; the failed one stays null.
    expect(photos[0]['serverKey'], 'Production/p0.jpg');
    expect(photos[1]['serverKey'], 'Production/p1.jpg');
    expect(photos[2]['serverKey'], isNull);
    expect(photos[3]['serverKey'], 'Production/p3.jpg');

    // Ran in parallel but never exceeded the concurrency bound.
    expect(api.calls, 4);
    expect(api.maxInFlight, greaterThan(1), reason: 'should upload in parallel');
    expect(api.maxInFlight, lessThanOrEqualTo(3), reason: 'bounded to 3');
  });

  test('already-uploaded photos are not re-uploaded', () async {
    final api = _FakeApi();
    final service = PhotoSyncService.forTest(apiService: api);
    final formData = {
      'Photo': [
        {
          'name': 'done.jpg',
          'localPath': files[0].path,
          'serverKey': 'Production/done.jpg',
          'serverUrl': 'https://oss/done.jpg',
          'created': DateTime(2026, 1, 1).toIso8601String(),
          'updated': DateTime(2026, 1, 1).toIso8601String(),
        },
      ],
    };

    await service.processFormDataForPush(formData, _project());

    expect(api.calls, 0, reason: 'photo with serverKey must not be re-uploaded');
  });
}
