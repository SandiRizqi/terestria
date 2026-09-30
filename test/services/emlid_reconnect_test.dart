import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geoform_app/services/location_service_v2.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connect ulang yang gagal tak boleh meninggalkan reconnect "hantu" dari
/// sesi sebelumnya (UI bilang gagal, padahal service terus mencoba di
/// belakang). Memakai socket loopback nyata — tanpa jaringan eksternal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'connect ulang yang langsung putus → false & tak ada reconnect terjadwal',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = LocationServiceV2();

    // Server 1: menerima & menjaga koneksi → connect sukses, auto-reconnect aktif.
    final keep = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final kept = <Socket>[];
    keep.listen(kept.add);
    // Server 2: menutup koneksi seketika.
    final drop = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    drop.listen((s) => s.destroy());
    addTearDown(() async {
      await service.disconnectEmlidTCP();
      for (final s in kept) {
        s.destroy();
      }
      await keep.close();
      await drop.close();
    });

    expect(
        await service.connectEmlidTCP(
            host: '127.0.0.1',
            port: keep.port,
            coordinateFormat: CoordinateFormat.llh),
        isTrue);
    expect(service.autoReconnectEnabled, isTrue);

    final ok = await service.connectEmlidTCP(
        host: '127.0.0.1',
        port: drop.port,
        coordinateFormat: CoordinateFormat.llh);

    expect(ok, isFalse);
    expect(service.autoReconnectEnabled, isFalse);
    expect(service.isReconnectScheduled, isFalse,
        reason: 'a failed connect must not keep reconnecting in the background');
  }, timeout: const Timeout(Duration(seconds: 30)));
}
