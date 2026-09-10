import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geoform_app/models/analysis/analysis_file_model.dart';
import 'package:geoform_app/services/analysis_pdf_downloader.dart';
import 'package:geoform_app/services/analysis_report_service.dart';

AnalysisReportService _reportServiceReturning(Map<String, dynamic> fileJson) {
  return AnalysisReportService(
    getter: (endpoint, {queryParameters}) async =>
        http.Response(jsonEncode({'success': true, 'data': fileJson}), 200),
  );
}

AnalysisFile _staleFile() => AnalysisFile.fromJson({
      'id': 12,
      'title': 'Peta_G03.pdf',
      'file_name': 'Peta G03.pdf',
      'download_url': 'https://oss/STALE',
      'content_type': 'application/pdf',
    });

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('analysis_dl_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('refreshes the signed URL then downloads bytes to a local file',
      () async {
    final report = _reportServiceReturning({
      'id': 12,
      'title': 'Peta_G03.pdf',
      'file_name': 'Peta G03.pdf',
      'download_url': 'https://oss/FRESH',
    });

    Uri? requestedUrl;
    final client = MockClient((request) async {
      requestedUrl = request.url;
      return http.Response.bytes([1, 2, 3, 4], 200);
    });

    final downloader = AnalysisPdfDownloader(
      reportService: report,
      client: client,
      tempDirProvider: () async => tempDir,
    );

    final path = await downloader.downloadPdf(_staleFile());

    // Downloaded from the freshly-refreshed URL, not the stale one.
    expect(requestedUrl.toString(), 'https://oss/FRESH');

    final file = File(path);
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), [1, 2, 3, 4]);
    expect(path.toLowerCase().endsWith('.pdf'), isTrue);
  });

  test('throws AnalysisDownloadException on a non-200 download', () async {
    final report = _reportServiceReturning({
      'id': 12,
      'title': 't',
      'file_name': 't.pdf',
      'download_url': 'https://oss/FRESH',
    });
    final client = MockClient((request) async => http.Response('nope', 403));

    final downloader = AnalysisPdfDownloader(
      reportService: report,
      client: client,
      tempDirProvider: () async => tempDir,
    );

    expect(
      () => downloader.downloadPdf(_staleFile()),
      throwsA(isA<AnalysisDownloadException>()),
    );
  });
}
