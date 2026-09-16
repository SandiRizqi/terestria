import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
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
        'paused': s.paused ? 1 : 0,
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
        paused: (row['paused'] as int) == 1,
        points: points,
      );

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

  Future<void> setPaused(String projectId, bool paused) async {
    final db = await _dbService.database;
    await db.update(
      'tracking_sessions',
      {'paused': paused ? 1 : 0, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
      where: 'projectId = ?',
      whereArgs: [projectId],
    );
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
  Future<List<TrackingSession>> restoreAll() async {
    final db = await _dbService.database;
    final rows = await db.query('tracking_sessions');
    final out = <TrackingSession>[];
    for (final row in rows) {
      final pid = row['projectId'] as String;
      final ptRows = await db.query('tracking_session_points',
          where: 'projectId = ?', whereArgs: [pid], orderBy: 'seq ASC');
      final points = ptRows.map(pointFromRow).toList();
      out.add(sessionFromRow(row, points));
    }
    return out;
  }
}
