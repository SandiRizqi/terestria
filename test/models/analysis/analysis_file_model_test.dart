import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/analysis/analysis_file_model.dart';

void main() {
  group('AnalysisFile.fromJson', () {
    test('parses full FileRow from contract sample', () {
      final json = {
        'id': 12,
        'title': 'Peta_Kerapatan_G03.pdf',
        'block_code': 'G03',
        'description': '',
        'file_name': 'Peta_Kerapatan_G03.pdf',
        'file_size': 1572864,
        'content_type': 'application/pdf',
        'download_url': 'https://tap-gis.oss-signed/url',
        'uploaded_by': 'anugrah.sandi',
        'created_at': '2026-07-23T09:24:00Z',
      };

      final file = AnalysisFile.fromJson(json);

      expect(file.id, 12);
      expect(file.title, 'Peta_Kerapatan_G03.pdf');
      expect(file.blockCode, 'G03');
      expect(file.fileName, 'Peta_Kerapatan_G03.pdf');
      expect(file.fileSize, 1572864);
      expect(file.contentType, 'application/pdf');
      expect(file.downloadUrl, 'https://tap-gis.oss-signed/url');
      expect(file.uploadedBy, 'anugrah.sandi');
      expect(file.createdAt, DateTime.parse('2026-07-23T09:24:00Z'));
    });

    test('applies safe defaults for absent optional fields', () {
      final json = {
        'id': 13,
        'title': 'x.pdf',
        'file_name': 'x.pdf',
        'download_url': 'https://signed/x',
      };

      final file = AnalysisFile.fromJson(json);

      expect(file.blockCode, '');
      expect(file.description, '');
      expect(file.fileSize, 0);
      expect(file.contentType, '');
      expect(file.uploadedBy, '');
      expect(file.createdAt, isNull);
    });

    test('isPdf reflects content type / extension', () {
      final pdf = AnalysisFile.fromJson({
        'id': 1,
        'title': 'a.pdf',
        'file_name': 'a.pdf',
        'download_url': 'u',
        'content_type': 'application/pdf',
      });
      final other = AnalysisFile.fromJson({
        'id': 2,
        'title': 'a.png',
        'file_name': 'a.png',
        'download_url': 'u',
        'content_type': 'image/png',
      });

      expect(pdf.isPdf, isTrue);
      expect(other.isPdf, isFalse);
    });

    test('fileSizeLabel formats bytes into human-readable units', () {
      AnalysisFile withSize(int bytes) => AnalysisFile.fromJson({
            'id': 1,
            'title': 't',
            'file_name': 't',
            'download_url': 'u',
            'file_size': bytes,
          });

      expect(withSize(0).fileSizeLabel, '0 B');
      expect(withSize(512).fileSizeLabel, '512 B');
      expect(withSize(1572864).fileSizeLabel, '1.5 MB');
    });

    test('copyWith replaces only the download url (for refresh)', () {
      final file = AnalysisFile.fromJson({
        'id': 12,
        'title': 't',
        'file_name': 't',
        'download_url': 'old',
      });

      final refreshed = file.copyWith(downloadUrl: 'fresh');

      expect(refreshed.downloadUrl, 'fresh');
      expect(refreshed.id, 12);
      expect(refreshed.title, 't');
    });
  });
}
