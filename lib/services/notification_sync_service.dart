import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_model.dart';
import 'api_service.dart';
import 'database_service.dart';
import 'notification_event_service.dart';

import '../utils/app_logger.dart';
/// Id lokal yang STABIL untuk sebuah notifikasi berdasarkan `data` FCM/server.
///
/// Push (FCM) dan hasil sync inbox server harus menghasilkan id yang sama agar
/// tidak dobel (tabel `notifications` PRIMARY KEY = id, upsert replace). Skema:
/// `"<type|notif>_<object_id>"`. Null bila tak ada `object_id`.
String? stableNotificationId(Map<String, dynamic>? data) {
  if (data == null) return null;
  final objectId = data['object_id'];
  if (objectId == null || '$objectId'.isEmpty) return null;
  final type = (data['type'] ?? 'notif').toString();
  return '${type}_$objectId';
}

/// Petakan satu item inbox server → [NotificationModel] dengan id stabil.
NotificationModel notificationFromServerItem(Map<String, dynamic> item) {
  final type = (item['model_name'] ?? 'notif').toString();
  final objectId = '${item['object_id'] ?? ''}';
  final data = <String, dynamic>{
    'type': type,
    'object_id': objectId,
    if (item['id'] != null) 'server_id': '${item['id']}',
    if (item['company_name'] != null) 'company_name': '${item['company_name']}',
    // Geometri hotspot (GeoJSON string) dari server → tombol "Lihat di Peta"
    // muncul & routing punya titik tujuan, sama seperti notifikasi push.
    if (item['map'] != null && '${item['map']}'.isNotEmpty)
      'map': '${item['map']}',
  };
  DateTime received;
  try {
    received = DateTime.parse('${item['created_at']}').toLocal();
  } catch (_) {
    received = DateTime.now();
  }
  return NotificationModel(
    id: stableNotificationId(data) ?? '${item['id']}',
    title: (item['title'] ?? '').toString(),
    body: (item['message'] ?? '').toString(),
    data: data,
    receivedAt: received,
    isRead: item['is_read'] == true,
  );
}

/// Item server yang BELUM ada di lokal (dedup by stable id).
List<NotificationModel> newServerItems(
    List<dynamic> items, Set<String> existingIds) {
  final result = <NotificationModel>[];
  for (final raw in items) {
    final model = notificationFromServerItem(Map<String, dynamic>.from(raw));
    if (existingIds.contains(model.id)) continue;
    result.add(model);
  }
  return result;
}

/// Baris lokal yang perlu DI-ENRICH `map`-nya dari server: id sudah ada lokal,
/// lokal belum punya `map`, server kini menyediakan `map`. Dibutuhkan karena
/// [newServerItems] melewati id yang sudah ada — notifikasi lama yang ter-sync
/// sebelum fitur ini takkan pernah dapat geometri tanpa enrich. isRead &
/// receivedAt LOKAL dipertahankan (read lokal bukan wewenang enrich ini).
List<NotificationModel> enrichableFromServer(
    List<dynamic> items, Map<String, NotificationModel> localById) {
  final out = <NotificationModel>[];
  for (final raw in items) {
    final server = notificationFromServerItem(Map<String, dynamic>.from(raw));
    final local = localById[server.id];
    if (local == null) continue;
    final localHasMap = local.data?.containsKey('map') ?? false;
    final serverHasMap = server.data?.containsKey('map') ?? false;
    if (!localHasMap && serverHasMap) {
      out.add(local.copyWith(
          data: {...?local.data, 'map': server.data!['map']}));
    }
  }
  return out;
}

/// Menarik inbox notifikasi dari server dan meng-upsert ke DB lokal —
/// menambal notifikasi yang push-nya tertunda/hilang (Doze). Push tetap jalan;
/// ini hanya jaring pengaman/rekonsiliasi.
class NotificationSyncService {
  static const String _lastSyncKey = 'notif_last_sync';
  // Sekali saja setelah update: abaikan `since` agar notifikasi lama ikut
  // tertarik & di-enrich map-nya (baris tanpa geometri dari sebelum fitur ini).
  static const String _mapBackfillKey = 'notif_map_backfill_v1';
  static const String endpoint = '/mobile/notifications/';

  final ApiService _api;
  final DatabaseService _db;
  final NotificationEventService _events;

  NotificationSyncService({
    ApiService? api,
    DatabaseService? db,
    NotificationEventService? events,
  })  : _api = api ?? ApiService(),
        _db = db ?? DatabaseService(),
        _events = events ?? NotificationEventService();

  /// Sinkron; kembalikan jumlah notifikasi baru yang dimasukkan. Aman dipanggil
  /// berkali-kali (dedup). Gagal jaringan → 0, tidak melempar.
  Future<int> sync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Sinkron pertama dibatasi 3 hari terakhir (bukan tarik-semua) agar query
      // ringan & tidak timeout; sesudahnya delta dari `_lastSyncKey`.
      final backfillDone = prefs.getBool(_mapBackfillKey) ?? false;
      final since = backfillDone
          ? prefs.getString(_lastSyncKey)
          : DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 3))
              .toIso8601String();
      var path = endpoint;
      if (since != null && since.isNotEmpty) {
        path = '$endpoint?since=${Uri.encodeComponent(since)}';
      }

      final resp = await _api.get(path);
      if (resp.statusCode != 200) return 0;

      final body = jsonDecode(resp.body);
      final List<dynamic> results =
          (body is Map && body['results'] is List) ? body['results'] : const [];

      final localList = await _db.loadNotifications();
      final existing = {for (final n in localList) n.id};
      final fresh = newServerItems(results, existing);
      for (final n in fresh) {
        await _db.saveNotification(n);
      }

      // Enrich baris lama yang sudah ada tapi belum punya `map` (dedup melewati
      // mereka). isRead lokal dipertahankan oleh enrichableFromServer.
      final localById = {for (final n in localList) n.id: n};
      final enriched = enrichableFromServer(results, localById);
      for (final n in enriched) {
        await _db.saveNotification(n);
      }

      await prefs.setString(
          _lastSyncKey, DateTime.now().toUtc().toIso8601String());
      await prefs.setBool(_mapBackfillKey, true);
      if (fresh.isNotEmpty) _events.notifyNewNotification();
      return fresh.length;
    } catch (e) {
      // Sync bersifat best-effort — jangan ganggu UI.
      // ignore: avoid_print
      logWarn('NotificationSyncService.sync gagal: $e', tag: 'NOTIF');
      return 0;
    }
  }

  /// Tandai sudah dibaca di server (best-effort). [serverId] dari
  /// `notification.data['server_id']`; null → dilewati.
  Future<void> markReadOnServer(String? serverId) async {
    if (serverId == null || serverId.isEmpty) return;
    try {
      await _api.post('$endpoint$serverId/read/');
    } catch (_) {/* best-effort */}
  }
}
