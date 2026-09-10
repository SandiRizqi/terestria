import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/analysis/analysis_company_model.dart';

void main() {
  group('AnalysisCompany.fromJson', () {
    test('parses full PT row from contract sample', () {
      final json = {
        'company_id': 20,
        'comp_name': 'PT NPN',
        'comp_code': 'NPN',
        'comp_group': 'TAP',
        'file_count': 16,
        'last_updated': '2026-07-23T09:24:00Z',
      };

      final company = AnalysisCompany.fromJson(json);

      expect(company.companyId, 20);
      expect(company.compName, 'PT NPN');
      expect(company.compCode, 'NPN');
      expect(company.compGroup, 'TAP');
      expect(company.fileCount, 16);
      expect(company.lastUpdated, DateTime.parse('2026-07-23T09:24:00Z'));
    });

    test('applies safe defaults and null date when fields absent/invalid', () {
      final json = {
        'company_id': 21,
        'comp_name': 'PT XYZ',
      };

      final company = AnalysisCompany.fromJson(json);

      expect(company.compCode, '');
      expect(company.compGroup, '');
      expect(company.fileCount, 0);
      expect(company.lastUpdated, isNull);
    });
  });
}
