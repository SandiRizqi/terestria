import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Penjaga regresi "Gagal membagikan: PlatformException(sharePositionOrigin)"
/// di iOS: setiap pemanggilan share_plus di lib/ wajib mengirim
/// `sharePositionOrigin` (pakai `shareOriginFor(context)`). Tanpa itu nilainya
/// {0,0,0,0} dan iOS menolak membuka share sheet.
void main() {
  test('semua pemanggilan share_plus mengirim sharePositionOrigin', () {
    final call = RegExp(r'\bShare\.(shareXFiles|shareUri|share)\(|\bShareParams\(');
    final violations = <String>[];

    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        final args = _argumentsFrom(src, m.end - 1);
        if (!args.contains('sharePositionOrigin')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          violations.add('${f.path}:$line');
        }
      }
    }

    expect(violations, isEmpty,
        reason: 'Tambahkan sharePositionOrigin: shareOriginFor(context)');
  });
}

/// Teks argumen dari '(' di [open] sampai ')' pasangannya.
String _argumentsFrom(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '(') depth++;
    if (c == ')' && --depth == 0) return src.substring(open, i + 1);
  }
  return src.substring(open);
}
