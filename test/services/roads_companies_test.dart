import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/routing_service.dart';

void main() {
  test('parseCompanies memetakan field + membuang id tak valid', () {
    const body = '{"success":true,"companies":['
        '{"id":14,"name":"PT DLJ2","road_count":10},'
        '{"id":18,"name":"PT EBL","road_count":0},'
        '{"id":0,"name":"x","road_count":5}]}';
    final list = parseCompanies(body);

    expect(list.length, 2); // id=0 difilter
    expect(list[0].id, 14);
    expect(list[0].name, 'PT DLJ2');
    expect(list[0].roadCount, 10);
    expect(list[0].hasData, isTrue);
    expect(list[1].id, 18);
    expect(list[1].hasData, isFalse); // road_count 0 → belum tersedia
  });

  test('parseCompanies aman utk body kosong/tak wajar', () {
    expect(parseCompanies('{}'), isEmpty);
    expect(parseCompanies('{"companies":[]}'), isEmpty);
    expect(parseCompanies('not json'), isEmpty);
  });
}
