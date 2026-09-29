/// Teks notifikasi persisten background untuk tracking multi-sesi, mis.
/// "Merekam 2 project · 1 jeda · 1 belum disimpan". Null bila tak ada sesi yang
/// merekam (service mati → tak ada notifikasi).
String? trackingNotificationText({
  required int recording,
  int paused = 0,
  int pending = 0,
}) {
  if (recording <= 0) return null;
  return [
    'Merekam $recording project',
    if (paused > 0) '$paused jeda',
    if (pending > 0) '$pending belum disimpan',
  ].join(' · ');
}

/// Peringatan saat mengganti provider GPS padahal [affected] sesi masih
/// merekam dengan sumber lama. Null bila tak ada yang terdampak.
String? providerSwitchWarningText(int affected) => affected <= 0
    ? null
    : '$affected project sedang merekam dengan sumber GPS saat ini. Setelah '
        'provider diganti, project tersebut berhenti menerima titik sampai '
        'provider dikembalikan. Lanjutkan?';
