import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';

/// Singleton wrapper around Firebase Crashlytics.
///
/// Centralises all error reporting so:
/// - Crashlytics can be swapped / mocked without touching call-sites
/// - Debug builds only log to console, never send to Crashlytics
/// - Every error is enriched with structured context (custom keys)
class CrashlyticsService {
  CrashlyticsService._();
  static final CrashlyticsService instance = CrashlyticsService._();

  FirebaseCrashlytics get _c => FirebaseCrashlytics.instance;

  // ─────────────────────────────────────────────────────────
  // Initialisation
  // ─────────────────────────────────────────────────────────

  /// Call once after Firebase.initializeApp().
  /// Wires up Flutter framework errors and async Dart errors.
  Future<void> initialize() async {
    // In debug builds, disable sending to Crashlytics (log locally only).
    await _c.setCrashlyticsCollectionEnabled(!kDebugMode);

    // 1. Flutter framework errors (widget build, layout, rendering)
    FlutterError.onError = (FlutterErrorDetails details) {
      if (kDebugMode) {
        // Show full error in debug console
        FlutterError.dumpErrorToConsole(details);
      } else {
        _c.recordFlutterFatalError(details);
      }
    };

    // 2. Async Dart errors not caught by Flutter framework
    PlatformDispatcher.instance.onError = (error, stack) {
      _recordErrorInternal(
        error,
        stack,
        fatal: true,
        reason: 'Uncaught async platform error',
      );
      return true; // Handled
    };

    logInfo('Crashlytics siap (kirim: ${!kDebugMode})', tag: 'CRASH');
  }

  // ─────────────────────────────────────────────────────────
  // User context
  // ─────────────────────────────────────────────────────────

  /// Attach user info to all subsequent crash reports.
  Future<void> setUser({
    required String userId,
    String? username,
  }) async {
    await _c.setUserIdentifier(userId);
    if (username != null) {
      await _c.setCustomKey('username', username);
    }
  }

  /// Clear user info (call on logout).
  Future<void> clearUser() async {
    await _c.setUserIdentifier('');
    await _c.setCustomKey('username', '');
  }

  // ─────────────────────────────────────────────────────────
  // Custom context keys
  // ─────────────────────────────────────────────────────────

  /// Set a key-value pair visible in the Crashlytics dashboard.
  /// Values are coerced to String, int, double, or bool automatically.
  Future<void> setContext(String key, dynamic value) async {
    try {
      if (value is bool) {
        await _c.setCustomKey(key, value);
      } else if (value is int) {
        await _c.setCustomKey(key, value);
      } else if (value is double) {
        await _c.setCustomKey(key, value);
      } else {
        await _c.setCustomKey(key, value?.toString() ?? '');
      }
    } catch (_) {
      // setCustomKey must not throw and crash the caller
    }
  }

  // ─────────────────────────────────────────────────────────
  // Breadcrumb logging
  // ─────────────────────────────────────────────────────────

  /// Add a breadcrumb log message that appears before a crash in the
  /// Crashlytics dashboard. Max 64 KB total across all logs.
  void log(String message) {
    addBreadcrumb(message);
    // Ikut ke berkas log; forward:false → tak dikirim ulang ke Crashlytics.
    AppLogger.log(LogLevel.info, message, tag: 'CRASH', forward: false);
  }

  /// Breadcrumb mentah (tanpa log berkas) — dipakai forwarder AppLogger.
  /// Aman dipanggil walau Firebase gagal init.
  void addBreadcrumb(String message) {
    try {
      _c.log('[${DateTime.now().toIso8601String()}] $message');
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────
  // Error recording
  // ─────────────────────────────────────────────────────────

  /// Record a **non-fatal** error.
  ///
  /// [reason] is a short human-readable label shown in the dashboard.
  /// [information] is a list of extra lines appended to the report.
  void recordError(
    dynamic error,
    StackTrace? stack, {
    String? reason,
    List<String> information = const [],
    bool fatal = false,
  }) {
    _recordErrorInternal(
      error,
      stack,
      reason: reason,
      information: information,
      fatal: fatal,
    );
  }

  /// Record a **fatal** error (will appear as a crash in the dashboard).
  void recordFatalError(dynamic error, StackTrace? stack, {String? reason}) {
    _recordErrorInternal(error, stack, fatal: true, reason: reason);
  }

  // ─────────────────────────────────────────────────────────
  // Internal
  // ─────────────────────────────────────────────────────────

  void _recordErrorInternal(
    dynamic error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
    List<String> information = const [],
  }) {
    // Selalu ke berkas log (debug & release); forward:false agar error ini tak
    // diteruskan balik ke Crashlytics oleh forwarder AppLogger.
    AppLogger.log(
      fatal ? LogLevel.error : LogLevel.warn,
      '${fatal ? "FATAL " : ""}${reason ?? "error"}',
      tag: 'CRASH',
      error: error,
      stack: stack,
      forward: false,
    );
    // Debug build: jangan habiskan kuota Crashlytics.
    if (kDebugMode) return;

    _c.recordError(
      error,
      stack,
      reason: reason,
      information: information.map((s) => DiagnosticsNode.message(s)).toList(),
      fatal: fatal,
      printDetails: false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Convenience top-level accessor so call-sites can write:
//   crashlytics.recordError(e, stack, reason: '...')
// instead of:
//   CrashlyticsService.instance.recordError(...)
// ─────────────────────────────────────────────────────────────────────────────
final crashlytics = CrashlyticsService.instance;
