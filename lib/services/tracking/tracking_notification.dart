/// Teks notifikasi persisten background untuk tracking multi-sesi, mis.
/// "Recording 2 projects · 1 paused · 1 not saved". Null bila tak ada sesi yang
/// merekam (service mati → tak ada notifikasi).
String? trackingNotificationText({
  required int recording,
  int paused = 0,
  int pending = 0,
}) {
  if (recording <= 0) return null;
  return [
    'Recording $recording project${recording == 1 ? '' : 's'}',
    if (paused > 0) '$paused paused',
    if (pending > 0) '$pending not saved',
  ].join(' · ');
}

/// Peringatan saat mengganti provider GPS padahal [affected] sesi masih
/// merekam dengan sumber lama. Null bila tak ada yang terdampak.
String? providerSwitchWarningText(int affected) => affected <= 0
    ? null
    : '$affected project${affected == 1 ? ' is' : 's are'} recording with the '
        'current GPS source. After switching, ${affected == 1 ? 'it stops' : 'they stop'} '
        'receiving points until you switch back. Continue?';
