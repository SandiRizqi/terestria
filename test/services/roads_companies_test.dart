import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/routing_service.dart';

void main() {
  test('parseCompanies memetakan field + membuang code kosong', () {
    const body = '{"success":true,"companies":['
        '{"id":1,"code":"DLJ2","name":"DLJ","road_count":10},'
        '{"id":2,"code":"EMP","name":"Empty","road_count":0},'
        '{"id":3,"code":"","name":"x","road_count":5}]}';
    final list = parseCompanies(body);

    expect(list.length, 2); // code kosong difilter
    expect(list[0].code, 'DLJ2');
    expect(list[0].name, 'DLJ');
    expect(list[0].roadCount, 10);
    expect(list[0].hasData, isTrue);
    expect(list[1].code, 'EMP');
    expect(list[1].hasData, isFalse); // road_count 0 → belum tersedia
  });

  test('parseCompanies aman utk body kosong/tak wajar', () {
    expect(parseCompanies('{}'), isEmpty);
    expect(parseCompanies('{"companies":[]}'), isEmpty);
    expect(parseCompanies('not json'), isEmpty);
  });
}
