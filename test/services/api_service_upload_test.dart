import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geoform_app/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late File tempFile;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('api_upload');
    tempFile = File('${dir.path}/photo.jpg')..writeAsBytesSync([1, 2, 3]);
  });

  tearDown(() {
    final parent = tempFile.parent;
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  group('ApiService.uploadFile', () {
    test('returns parsed body on 2xx', () async {
      final api = ApiService.forTest(
        client: MockClient((req) async =>
            http.Response('{"success":true,"file_url":"u","key":"k"}', 200)),
      );

      final result = await api.uploadFile('https://x/uploadfile/', tempFile);

      expect(result, isNotNull);
      expect(result!['key'], 'k');
    });

    test('returns null on non-2xx without throwing', () async {
      final api = ApiService.forTest(
        client: MockClient((req) async => http.Response('server error', 500)),
      );

      final result = await api.uploadFile('https://x/uploadfile/', tempFile);

      expect(result, isNull);
    });

    test('returns null instead of hanging when upload exceeds timeout',
        () async {
      final api = ApiService.forTest(
        client: MockClient((req) async {
          await Future.delayed(const Duration(milliseconds: 300));
          return http.Response('{"success":true}', 200);
        }),
      );

      final result = await api.uploadFile(
        'https://x/uploadfile/',
        tempFile,
        timeout: const Duration(milliseconds: 50),
      );

      expect(result, isNull);
    });
  });
}
