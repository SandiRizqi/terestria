import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/utils/record_selection.dart';

/// Pilihan record di daftar data project (mode pilih).

void main() {
  test('kosong di awal', () {
    const s = RecordSelection();
    expect(s.isEmpty, isTrue);
    expect(s.count, 0);
  });

  test('toggle menambah lalu melepas', () {
    final s = const RecordSelection().toggle('a');
    expect(s.contains('a'), isTrue);
    expect(s.count, 1);
    expect(s.toggle('a').isEmpty, isTrue);
  });

  test('pilih semua = semua record yang terlihat', () {
    final s = const RecordSelection().toggle('a').toggleAll(['a', 'b', 'c']);
    expect(s.ids, {'a', 'b', 'c'});
    expect(s.allSelected(['a', 'b', 'c']), isTrue);
  });

  test('pilih semua saat semuanya sudah terpilih = lepas semua', () {
    final s = const RecordSelection().toggleAll(['a', 'b']).toggleAll(['a', 'b']);
    expect(s.isEmpty, isTrue);
  });

  test('daftar terlihat kosong tidak dianggap "semua terpilih"', () {
    expect(const RecordSelection().allSelected(const []), isFalse);
  });

  test('retain melepas record yang tidak terlihat lagi (filter/hapus)', () {
    final s = const RecordSelection().toggleAll(['a', 'b', 'c']).retain(['b', 'x']);
    expect(s.ids, {'b'});
  });
}
