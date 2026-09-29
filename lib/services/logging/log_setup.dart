import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils/app_logger.dart';
import 'app_log.dart';
import 'diagnostic_mode.dart';

/// Folder log bersama semua isolate: `<documents>/logs`.
Future<Directory> logsDirectory() async {
  final docs = await getApplicationDocumentsDirectory();
  return Directory('${docs.path}/logs');
}

/// Pasang logger berkas untuk isolate ini. [source]: `app` (UI) atau `bg`
/// (isolate background) — berkas terpisah agar dua isolate tak saling tulis.
/// Gagal init (mis. path_provider) → logger tetap jalan tanpa berkas.
Future<void> initAppLogging({required String source}) async {
  try {
    final sink = AppLogSink(dir: await logsDirectory(), source: source);
    AppLogger.attach(sink);
    AppLogger.setDiagnosticUntil(await DiagnosticMode.load());
    await sink.prune();
    logInfo('Logging siap (source=$source, diagnostik=${AppLogger.diagnosticActive})',
        tag: 'LOG');
  } catch (e) {
    AppLogger.detach();
  }
}

/// Catat error Flutter/platform yang tak tertangkap ke berkas, TANPA mengganti
/// handler yang sudah ada (Crashlytics tetap menerima). Panggil setelah
/// Crashlytics dipasang.
void installErrorLogging() {
  final previousFlutter = FlutterError.onError;
  FlutterError.onError = (details) {
    logError('Flutter error: ${details.exceptionAsString()}',
        tag: 'FLUTTER', stack: details.stack);
    previousFlutter?.call(details);
  };

  final previousPlatform = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    logError('Uncaught async error', tag: 'APP', error: error, stack: stack);
    return previousPlatform?.call(error, stack) ?? false;
  };
}
