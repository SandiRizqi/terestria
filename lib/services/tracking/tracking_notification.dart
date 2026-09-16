/// Teks notifikasi persisten background untuk tracking multi-sesi.
/// Null bila tak ada sesi aktif (notifikasi tak perlu ditampilkan).
String? trackingNotificationText(int activeCount) =>
    activeCount <= 0 ? null : 'Tracking $activeCount project aktif';
