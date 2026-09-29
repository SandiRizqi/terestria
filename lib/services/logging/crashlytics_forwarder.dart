import 'app_log.dart';

/// Meneruskan log warn/error ke Crashlytics sebagai breadcrumb, sehingga
/// laporan crash dari lapangan membawa riwayat kejadian terakhir tanpa user
/// mengirim apa pun. Error yang membawa objek error juga dicatat sebagai
/// non-fatal — dibatasi 1× per [window] per pesan agar dashboard tak banjir.
class CrashlyticsLogForwarder {
  CrashlyticsLogForwarder({
    required void Function(String message) breadcrumb,
    required void Function(Object error, StackTrace? stack, String reason)
        recordError,
    DateTime Function()? now,
    this.window = const Duration(minutes: 5),
  })  : _breadcrumb = breadcrumb,
        _recordError = recordError,
        _now = now ?? DateTime.now;

  static const _maxCrumb = 1000;
  static const _letters = {LogLevel.warn: 'W', LogLevel.error: 'E'};

  final void Function(String) _breadcrumb;
  final void Function(Object, StackTrace?, String) _recordError;
  final DateTime Function() _now;
  final Duration window;
  final Map<String, DateTime> _lastRecorded = {};

  void call(LogLevel level, String tag, String message,
      [Object? error, StackTrace? stack]) {
    final letter = _letters[level];
    if (letter == null) return; // debug/info tak dikirim
    final crumb = '$letter $tag $message';
    _breadcrumb(
        crumb.length > _maxCrumb ? crumb.substring(0, _maxCrumb) : crumb);

    if (level != LogLevel.error || error == null) return;
    final reason = '$tag: $message';
    final now = _now();
    final last = _lastRecorded[reason];
    if (last != null && now.difference(last) < window) return;
    _lastRecorded[reason] = now;
    _recordError(error, stack, reason);
  }
}
