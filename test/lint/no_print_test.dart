import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gerbang: semua log lewat `lib/utils/app_logger.dart` (logDebug/logInfo/
/// logWarn/logError). `print`/`debugPrint` langsung tidak boleh ada di `lib/`
/// — di build release keduanya hanya mengotori logcat dan tak tersimpan ke
/// berkas log yang bisa dibagikan. (`avoid_print` di analysis_options hanya
/// menangkap `print`, tidak `debugPrint`.)
void main() {
  final call = RegExp(r'(?<![\w.$])(print|debugPrint)\s*\(');

  bool inLineComment(String line, int col) {
    final before = line.substring(0, col).replaceAll(RegExp(r"'[^']*'|" r'"[^"]*"'), '');
    return before.contains('//') || before.trimLeft().startsWith('*');
  }

  test('tak ada print()/debugPrint() di lib/ selain app_logger.dart', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll('\\', '/');
      if (path.endsWith('lib/utils/app_logger.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in call.allMatches(lines[i])) {
          if (!inLineComment(lines[i], m.start)) {
            offenders.add('$path:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Pakai logDebug/logInfo/logWarn/logError (lib/utils/app_logger.dart):\n'
            '${offenders.join('\n')}');
  });
}
