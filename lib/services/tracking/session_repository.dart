import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import '../../utils/app_logger.dart';
import '../database_service.dart';
import 'tracking_session.dart';

/// Persistensi sesi tracking di SQLite untuk recovery (crash/kill). Titik
/// disimpan **append-only** per (projectId, seq) agar flush batched murah —
/// hanya insert titik baru, tak menulis ulang seluruh jalur.
///
/// Hot-path UI tetap pakai list in-memory di [TrackingSessionManager]; repo ini
/// hanya cadangan tahan-lama.
class SessionRepository {
  final DatabaseService _dbService;
  SessionRepository([DatabaseService? dbService])
      : _dbService = dbService ?? DatabaseService();

  // ─── Serialisasi baris (murni, teruji) ───────────────────────────────────
  static Map<String, Object?> sessionRow(TrackingSession s) => {
        'projectId': s.projectId,
        'projectJson': jsonEncode(s.project.toJson()),
        'startedAt': s.startedAt.millisecondsSinceEpoch,
        // Kolom lama `paused` menyimpan kode SessionState: 0/1/2.
        'paused': s.state.index,
        'provider': s.source.name,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  static Map<String, Object?> pointRow(String projectId, int seq, GeoPoint p) =>
      {
        'projectId': projectId,
        'seq': seq,
        'point': jsonEncode(p.toJson()),
      };

  static TrackingSession sessionFromRow(
          Map<String, Object?> row, List<GeoPoint> points) =>
      TrackingSession(
        project:
            Project.fromJson(jsonDecode(row['projectJson'] as String) as Map<String, dynamic>),
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(row['startedAt'] as int),
        state: stateFromCode(row['paused'] as int?),
        source: TrackSource.values.firstWhere(
          (v) => v.name == row['provider'],
          orElse: () => TrackSource.phone, // baris lama (DB v4)
        ),
        points: points,
      );

  /// Migrasi v5: tambah kolom `provider` hanya bila belum ada (hasil
  /// `PRAGMA table_info(tracking_sessions)`) — aman dijalankan berulang.
  static bool needsProviderColumn(List<Map<String, Object?>> tableInfo) =>
      !tableInfo.any((c) => c['name'] == 'provider');

  /// Kode kolom → status; nilai tak dikenal diperlakukan paused (aman: tak
  /// merekam diam-diam, tetap bisa dilanjutkan/disimpan user).
  static SessionState stateFromCode(int? code) =>
      (code != null && code >= 0 && code < SessionState.values.length)
          ? SessionState.values[code]
          : SessionState.paused;

  static GeoPoint pointFromRow(Map<String, Object?> row) =>
      GeoPoint.fromJson(jsonDecode(row['point'] as String) as Map<String, dynamic>);

  // ─── Operasi DB ──────────────────────────────────────────────────────────

  /// Simpan/replace baris sesi (tanpa titik).
  Future<void> upsertSession(TrackingSession s) async {
    final db = await _dbService.database;
    await db.insert('tracking_sessions', sessionRow(s),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Tambah titik baru mulai [fromSeq] (batched insert).
  Future<void> appendPoints(
      String projectId, List<GeoPoint> newPoints, int fromSeq) async {
    if (newPoints.isEmpty) return;
    final db = await _dbService.database;
    final batch = db.batch();
    for (var i = 0; i < newPoints.length; i++) {
      batch.insert('tracking_session_points',
          pointRow(projectId, fromSeq + i, newPoints[i]),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// Tulis ulang seluruh titik sesi (setelah undo/clear) dalam satu batch.
  Future<void> replacePoints(String projectId, List<GeoPoint> points) async {
    final db = await _dbService.database;
    final batch = db.batch();
    batch.delete('tracking_session_points',
        where: 'projectId = ?', whereArgs: [projectId]);
    for (var i = 0; i < points.length; i++) {
      batch.insert('tracking_session_points', pointRow(projectId, i, points[i]));
    }
    await batch.commit(noResult: true);
  }

  /// Hapus sesi + titiknya (dipakai saat stop/save selesai).
  Future<void> deleteSession(String projectId) async {
    final db = await _dbService.database;
    final batch = db.batch();
    batch.delete('tracking_session_points',
        where: 'projectId = ?', whereArgs: [projectId]);
    batch.delete('tracking_sessions',
        where: 'projectId = ?', whereArgs: [projectId]);
    await batch.commit(noResult: true);
  }

  /// Muat semua sesi tersimpan + titiknya (urut seq) untuk restore saat start.
  ///
  /// Toleran terhadap baris rusak: sesi yang tak bisa di-parse dilewati (baris
  /// DB-nya DIBIARKAN, tak dihapus) dan titik rusak dilewati satu per satu,
  /// sehingga satu baris korup tak menggagalkan pemulihan sesi lain.
  Future<List<TrackingSession>> restoreAll() async {
    final db = await _dbService.database;
    final rows = await db.query('tracking_sessions');
    final out = <TrackingSession>[];
    for (final row in rows) {
      final pid = row['projectId'];
      try {
        final ptRows = await db.query('tracking_session_points',
            where: 'projectId = ?', whereArgs: [pid], orderBy: 'seq ASC');
        final points = <GeoPoint>[];
        var corrupt = 0;
        for (final r in ptRows) {
          try {
            points.add(pointFromRow(r));
          } catch (_) {
            corrupt++;
          }
        }
        if (corrupt > 0) {
          logWarn('Session $pid: skipped $corrupt corrupt point(s) on restore',
              tag: 'PERSIST');
        }
        out.add(sessionFromRow(row, points));
      } catch (e, st) {
        logError('Session $pid could not be restored (row kept in DB)',
            tag: 'PERSIST', error: e, stack: st);
      }
    }
    return out;
  }
}
