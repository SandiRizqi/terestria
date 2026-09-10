import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/models/analysis/analysis_type_model.dart';

void main() {
  group('AnalysisType.fromJson', () {
    test('parses full payload from contract sample', () {
      final json = {
        'id': 1,
        'name': 'Analisa Pokok Rapat',
        'code': 'analisa-pokok-rapat',
        'description': '',
        'icon': '',
        'company_count': 1,
      };

      final type = AnalysisType.fromJson(json);

      expect(type.id, 1);
      expect(type.name, 'Analisa Pokok Rapat');
      expect(type.code, 'analisa-pokok-rapat');
      expect(type.description, '');
      expect(type.icon, '');
      expect(type.companyCount, 1);
    });

    test('applies safe defaults for absent optional fields', () {
      final json = {
        'id': 2,
        'name': 'Kerapatan',
        'code': 'kerapatan',
      };

      final type = AnalysisType.fromJson(json);

      expect(type.description, '');
      expect(type.icon, '');
      expect(type.companyCount, 0);
    });
  });
}
