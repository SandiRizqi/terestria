/// Teks notifikasi persisten background untuk tracking multi-sesi.
/// Null bila tak ada sesi aktif (notifikasi tak perlu ditampilkan).
String? trackingNotificationText(int activeCount) =>
    activeCount <= 0 ? null : 'Tracking $activeCount project aktif';

/// Peringatan saat mengganti provider GPS padahal [affected] sesi masih
/// merekam dengan sumber lama. Null bila tak ada yang terdampak.
String? providerSwitchWarningText(int affected) => affected <= 0
    ? null
    : '$affected project sedang merekam dengan sumber GPS saat ini. Setelah '
        'provider diganti, project tersebut berhenti menerima titik sampai '
        'provider dikembalikan. Lanjutkan?';
