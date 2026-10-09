import 'package:intl/intl.dart';

/// Waktu relatif singkat: "just now", "5 min ago", "2 h ago", "yesterday",
/// "5 d ago", lalu tanggal ("1 Sep", "31 Dec 2025"). Waktu di masa depan
/// (jam HP tidak cocok) dianggap "just now".
String relativeTime(DateTime time, DateTime now) {
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';

  // Hari kalender (UTC agar selisih hari tidak terpengaruh pergantian jam).
  final days = DateTime.utc(now.year, now.month, now.day)
      .difference(DateTime.utc(time.year, time.month, time.day))
      .inDays;
  if (days == 0) return '${diff.inHours} h ago';
  if (days == 1) return 'yesterday';
  if (days < 7) return '$days d ago';
  if (time.year == now.year) return DateFormat('d MMM').format(time);
  return DateFormat('d MMM yyyy').format(time);
}
