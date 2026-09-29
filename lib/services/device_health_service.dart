import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// Tingkat ruang penyimpanan kosong.
enum StorageLevel { ok, low, critical, unknown }

/// Ambang ruang kosong: di bawah [lowStorageBytes] → peringatan; di bawah
/// [criticalStorageBytes] → aksi berat (tracking, foto, unduh peta) meminta
/// konfirmasi karena penyimpanan bisa gagal di tengah jalan.
const int lowStorageBytes = 500 * 1024 * 1024;
const int criticalStorageBytes = 150 * 1024 * 1024;

StorageLevel storageLevelFor(int? freeBytes) {
  if (freeBytes == null || freeBytes < 0) return StorageLevel.unknown;
  if (freeBytes < criticalStorageBytes) return StorageLevel.critical;
  if (freeBytes < lowStorageBytes) return StorageLevel.low;
  return StorageLevel.ok;
}

String formatBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

/// Langkah menonaktifkan pembatasan baterai per merek HP (Android). Banyak
/// OEM mematikan service GPS di background walau notifikasi aktif.
String batteryGuidanceFor(String? manufacturer) {
  final m = (manufacturer ?? '').toLowerCase();
  if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) {
    return 'Settings → Apps → Terestria → Battery saver → "No restrictions", '
        'and turn on "Autostart".';
  }
  if (m.contains('oppo') || m.contains('realme') || m.contains('oneplus')) {
    return 'Settings → Battery → App battery management → Terestria → allow '
        'background activity.';
  }
  if (m.contains('vivo') || m.contains('iqoo')) {
    return 'Settings → Battery → Background power consumption management → '
        'Terestria → Allow.';
  }
  if (m.contains('samsung')) {
    return 'Settings → Apps → Terestria → Battery → "Unrestricted", and make '
        'sure Terestria is not in "Sleeping apps".';
  }
  if (m.contains('huawei') || m.contains('honor')) {
    return 'Settings → Battery → App launch → Terestria → "Manage manually" '
        'with all switches on.';
  }
  return 'Settings → Apps → Terestria → Battery → "Unrestricted" '
      '(or "Don\'t optimize").';
}

/// Info kesehatan perangkat dari native (ruang kosong, optimasi baterai).
/// Semua method aman: bila channel native tak tersedia/gagal → null (tak
/// diketahui) dan dicatat di log, tak pernah melempar ke UI.
class DeviceHealthService {
  static final DeviceHealthService _instance = DeviceHealthService._();
  factory DeviceHealthService() => _instance;
  DeviceHealthService._();

  static const MethodChannel _channel =
      MethodChannel('io.github.sandirizqi.terestria/device_health');

  Future<T?> _call<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null; // platform tanpa implementasi (mis. desktop/test)
    } on PlatformException catch (e) {
      logWarn('Device health "$method" failed: ${e.code} ${e.message}',
          tag: 'DEVICE');
      return null;
    } catch (e, st) {
      logWarn('Device health "$method" failed',
          tag: 'DEVICE', error: e, stack: st);
      return null;
    }
  }

  /// Ruang kosong penyimpanan app (byte), null bila tak diketahui.
  Future<int?> freeDiskBytes() => _call<int>('getFreeDiskBytes');

  Future<StorageLevel> storageLevel() async =>
      storageLevelFor(await freeDiskBytes());

  /// Android: true bila app dikecualikan dari optimasi baterai. Null di iOS
  /// atau bila tak diketahui.
  Future<bool?> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return null;
    return _call<bool>('isIgnoringBatteryOptimizations');
  }

  /// Buka pengaturan optimasi baterai (Android). False bila gagal.
  Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    final opened = await _call<bool>('openBatteryOptimizationSettings');
    return opened ?? false;
  }

  Future<String?> manufacturer() async {
    if (!Platform.isAndroid) return null;
    return _call<String>('getManufacturer');
  }
}

/// Sebelum aksi yang butuh ruang (tracking, foto, unduh peta): bila ruang
/// kosong kritis, tanya user. True = lanjut.
Future<bool> confirmStorageFor(BuildContext context,
    {required String action}) async {
  final free = await DeviceHealthService().freeDiskBytes();
  final level = storageLevelFor(free);
  if (level != StorageLevel.critical || !context.mounted) return true;
  logWarn('Low storage before "$action": ${formatBytes(free!)} free',
      tag: 'DEVICE');
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.sd_storage_outlined,
          color: Colors.orange.shade800, size: 36),
      title: const Text('Storage almost full'),
      content: Text(
        'Only ${formatBytes(free)} is free on this phone. $action may fail '
        'and data might not be saved.\n\nFree up space (old photos, videos, '
        'offline maps) before continuing.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continue anyway'),
        ),
      ],
    ),
  );
  return proceed ?? false;
}
