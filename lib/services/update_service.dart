import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';

/// Handles Google Play In-App Updates.
///
/// - Priority 0–3 → Flexible update (background download, user stays in app)
/// - Priority 4–5 → Immediate update (fullscreen overlay, must update to continue)
///
/// Safe to call when offline — all errors are silently swallowed so the app
/// continues to work normally without internet.
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  /// Cek update satu kali per sesi. Flag ini mencegah pengecekan berulang
  /// jika [checkForUpdate] dipanggil lebih dari sekali.
  bool _hasCheckedThisSession = false;

  /// Mulai pengecekan update secara async (fire-and-forget).
  ///
  /// Panggil ini tanpa `await` dari AppInitializer supaya tidak memblokir
  /// inisialisasi app.
  void startUpdateCheck(BuildContext? context) {
    // In-app update = Google Play Core → Android saja. Di iOS no-op senyap
    // supaya tidak melempar PlatformException.
    if (!Platform.isAndroid) return;
    if (_hasCheckedThisSession) return;
    _hasCheckedThisSession = true;

    // Fire-and-forget: tidak memblokir startup app
    _checkForUpdate(context).catchError((e) {
      debugPrint('⚠️ [UpdateService] Uncaught error in update check: $e');
    });
  }

  Future<void> _checkForUpdate(BuildContext? context) async {
    try {
      // Timeout 8 detik: kalau sinyal lemah, tidak akan freeze lama
      final AppUpdateInfo info = await InAppUpdate.checkForUpdate()
          .timeout(const Duration(seconds: 8));

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        debugPrint('✅ [UpdateService] App sudah versi terbaru');
        return;
      }

      final int priority = info.updatePriority ?? 0;
      debugPrint('🔄 [UpdateService] Update tersedia, priority: $priority');

      if (priority >= 4) {
        // Priority tinggi → Immediate update (wajib sebelum lanjut pakai app)
        await _startImmediateUpdate();
      } else {
        // Priority rendah/sedang → Flexible update (di background)
        await _startFlexibleUpdate(context);
      }
    } catch (e) {
      // Offline, Play Store tidak tersedia, atau timeout → skip saja
      debugPrint('⚠️ [UpdateService] Update check dilewati: $e');
    }
  }

  Future<void> _startImmediateUpdate() async {
    try {
      await InAppUpdate.performImmediateUpdate();
      debugPrint('✅ [UpdateService] Immediate update selesai');
    } catch (e) {
      debugPrint('⚠️ [UpdateService] Immediate update gagal: $e');
    }
  }

  Future<void> _startFlexibleUpdate(BuildContext? context) async {
    try {
      await InAppUpdate.startFlexibleUpdate();
      debugPrint('✅ [UpdateService] Flexible update dimulai (download background)');

      // Setelah download selesai, tampilkan snackbar jika context tersedia
      if (context != null && context.mounted) {
        _showFlexibleUpdateSnackbar(context);
      }
    } catch (e) {
      debugPrint('⚠️ [UpdateService] Flexible update gagal: $e');
    }
  }

  /// Tampilkan snackbar yang mengajak user untuk restart dan menerapkan update.
  /// Dipanggil baik dari dalam service maupun dari main.dart saat resume.
  void showInstallSnackbar(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Update sudah didownload dan siap diterapkan.'),
        duration: const Duration(seconds: 10),
        action: SnackBarAction(
          label: 'RESTART',
          onPressed: () {
            InAppUpdate.completeFlexibleUpdate().catchError((e) {
              debugPrint('⚠️ [UpdateService] completeFlexibleUpdate error: $e');
            });
          },
        ),
      ),
    );
  }

  // Private alias dipakai internal
  void _showFlexibleUpdateSnackbar(BuildContext context) =>
      showInstallSnackbar(context);
}
