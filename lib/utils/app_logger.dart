import 'package:flutter/foundation.dart';

import '../services/logging/app_log.dart';
import '../services/logging/diagnostic_mode.dart';

export '../services/logging/app_log.dart' show LogLevel;

/// Logger tunggal app — aman dipakai di isolate background (tiap isolate
/// memasang sink-nya sendiri lewat `initAppLogging`).
///
/// - Konsol (`debugPrint`) hanya di build debug → build release bersih.
/// - Berkas: `info`/`warn`/`error` selalu ditulis; `debug` hanya saat
///   Mode Diagnostik aktif (hot path GPS tak membebani I/O normalnya).
///
/// Ini SATU-SATUNYA tempat yang boleh memanggil `debugPrint`/`print`.
class AppLogger {
  static AppLogSink? _sink;
  static DateTime? _diagnosticUntil;

  static DateTime Function() now = DateTime.now;
  static bool consoleEnabled = kDebugMode;

  /// Diteruskan untuk warn/error (mis. breadcrumb Crashlytics di isolate app).
  static void Function(LogLevel level, String tag, String message)? onWarnOrError;

  static AppLogSink? get sink => _sink;
  static void attach(AppLogSink sink) => _sink = sink;
  static void detach() => _sink = null;

  static void setDiagnosticUntil(DateTime? until) => _diagnosticUntil = until;
  static DateTime? get diagnosticUntil => _diagnosticUntil;
  static bool get diagnosticActive =>
      DiagnosticMode.isActive(_diagnosticUntil, now());

  static void log(LogLevel level, String message, {String tag = 'APP'}) {
    if (consoleEnabled) debugPrint('[$tag] $message');
    final sink = _sink;
    if (sink != null && (level != LogLevel.debug || diagnosticActive)) {
      sink.write(level, tag, message);
    }
    if (level == LogLevel.warn || level == LogLevel.error) {
      onWarnOrError?.call(level, tag, message);
    }
  }

  /// Tulis semua buffer ke berkas (mis. sebelum ekspor / app di-kill).
  static Future<void> flush() async {
    final sink = _sink;
    if (sink == null) return;
    await sink.flush();
  }
}

/// Detail verbose (per fix GPS, per tile) — ke berkas hanya di Mode Diagnostik.
void logDebug(String message, {String tag = 'APP'}) =>
    AppLogger.log(LogLevel.debug, message, tag: tag);

/// Kejadian penting (sesi mulai/berhenti, service start/stop).
void logInfo(String message, {String tag = 'APP'}) =>
    AppLogger.log(LogLevel.info, message, tag: tag);

/// Kondisi tak normal yang masih bisa dipulihkan.
void logWarn(String message, {String tag = 'APP'}) =>
    AppLogger.log(LogLevel.warn, message, tag: tag);

/// Kegagalan. Sertakan [error]/[stack] bila ada.
void logError(String message,
    {String tag = 'APP', Object? error, StackTrace? stack}) {
  final detail = [
    message,
    if (error != null) '$error',
    if (stack != null) '$stack',
  ].join('\n');
  AppLogger.log(LogLevel.error, detail, tag: tag);
}
