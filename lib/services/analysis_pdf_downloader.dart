import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/analysis/analysis_file_model.dart';
import 'analysis_report_service.dart';

/// Mengunduh file PDF sebuah [AnalysisFile] dari OSS ke penyimpanan lokal,
/// setelah me-refresh `download_url` yang bertanda tangan & kedaluwarsa +-1 jam.
///
/// Catatan: URL OSS sudah pre-signed — unduhan TIDAK menyertakan header
/// Authorization (hanya refresh URL, lewat [AnalysisReportService], yang
/// memakai token).
class AnalysisPdfDownloader {
  final AnalysisReportService _reportService;
  final http.Client _client;
  final Future<Directory> Function() _tempDirProvider;

  AnalysisPdfDownloader({
    AnalysisReportService? reportService,
    http.Client? client,
    Future<Directory> Function()? tempDirProvider,
  })  : _reportService = reportService ?? AnalysisReportService(),
        _client = client ?? http.Client(),
        _tempDirProvider = tempDirProvider ?? getTemporaryDirectory;

  /// Refresh URL lalu unduh PDF; kembalikan path file lokal.
  Future<String> downloadPdf(AnalysisFile file) async {
    // Ambil download_url fresh tepat sebelum mengunduh (URL lama bisa expired).
    final fresh = await _reportService.fetchFileDetail(file.id);
    final url = fresh.downloadUrl;
    if (url.isEmpty) {
      throw AnalysisDownloadException('This file has no download link.');
    }

    final response = await _client.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw AnalysisDownloadException(
          'Could not download the file (server error ${response.statusCode}).');
    }

    final dir = await _tempDirProvider();
    final path = '${dir.path}/${_safeFileName(file)}';
    await File(path).writeAsBytes(response.bodyBytes);
    return path;
  }

  /// Nama file lokal aman (hindari karakter aneh, pastikan berakhiran .pdf,
  /// dan unik per file id agar tidak bentrok).
  String _safeFileName(AnalysisFile file) {
    final raw =
        file.fileName.isNotEmpty ? file.fileName : 'analysis_${file.id}.pdf';
    var name = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (!name.toLowerCase().endsWith('.pdf')) {
      name = '$name.pdf';
    }
    return 'analysis_${file.id}_$name';
  }
}

/// Kegagalan saat mengunduh file analisis.
class AnalysisDownloadException implements Exception {
  final String message;
  AnalysisDownloadException(this.message);

  @override
  String toString() => 'AnalysisDownloadException: $message';
}
