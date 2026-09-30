import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/geo_data_model.dart';
import '../utils/app_logger.dart';

/// Draft pengambilan data per project: titik manual (mode point/drawing,
/// tanpa sesi tracking) + isian form yang belum disimpan.
///
/// Di HP RAM kecil, membuka kamera sering membuat Android membunuh app; tanpa
/// draft, titik & isian form hilang. Titik sesi tracking sudah dicadangkan
/// terpisah oleh TrackingPersistenceCoordinator.
class CollectionDraft {
  final List<GeoPoint> points;
  final Map<String, dynamic> formData;
  final DateTime savedAt;

  const CollectionDraft({
    required this.points,
    required this.formData,
    required this.savedAt,
  });

  bool get isEmpty => points.isEmpty && formData.isEmpty;

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => p.toJson()).toList(),
        'formData': formData,
        'savedAt': savedAt.toUtc().toIso8601String(),
      };

  factory CollectionDraft.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];
    final rawForm = json['formData'];
    return CollectionDraft(
      points: rawPoints is List
          ? rawPoints
              .map((p) => GeoPoint.fromJson(Map<String, dynamic>.from(p as Map)))
              .toList()
          : const [],
      formData: rawForm is Map ? Map<String, dynamic>.from(rawForm) : {},
      savedAt: DateTime.tryParse(json['savedAt']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
  }
}

class CollectionDraftService {
  static const _prefix = 'collection_draft_';

  /// Nilai form yang layak disimpan sebagai draft: JSON-encodable saja.
  static Map<String, dynamic> _sanitize(Map<String, dynamic> formData) {
    final out = <String, dynamic>{};
    formData.forEach((k, v) {
      try {
        jsonEncode(v);
        out[k] = v;
      } catch (_) {
        out[k] = v?.toString();
      }
    });
    return out;
  }

  Future<void> save(
    String projectId, {
    required List<GeoPoint> points,
    required Map<String, dynamic> formData,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = CollectionDraft(
        points: points,
        formData: _sanitize(formData),
        savedAt: DateTime.now(),
      );
      if (draft.isEmpty) {
        await prefs.remove('$_prefix$projectId');
        return;
      }
      await prefs.setString('$_prefix$projectId', jsonEncode(draft.toJson()));
    } catch (e, st) {
      logWarn('Could not save collection draft for $projectId',
          tag: 'DRAFT', error: e, stack: st);
    }
  }

  Future<CollectionDraft?> load(String projectId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$projectId');
      if (raw == null) return null;
      final draft = CollectionDraft.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      return draft.isEmpty ? null : draft;
    } catch (e, st) {
      logWarn('Unreadable collection draft for $projectId — discarded',
          tag: 'DRAFT', error: e, stack: st);
      await clear(projectId);
      return null;
    }
  }

  /// Semua draft tersimpan (projectId → draft) — dipakai dialog logout &
  /// cadangan ZIP (logout menghapus draft). Draft kosong/rusak dilewati.
  Future<Map<String, CollectionDraft>> listDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final out = <String, CollectionDraft>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final projectId = key.substring(_prefix.length);
      try {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final draft = CollectionDraft.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
        if (!draft.isEmpty) out[projectId] = draft;
      } catch (e) {
        logWarn('Unreadable collection draft for $projectId — skipped: $e',
            tag: 'DRAFT');
      }
    }
    return out;
  }

  Future<void> clear(String projectId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$projectId');
    } catch (e) {
      logWarn('Could not clear collection draft for $projectId: $e',
          tag: 'DRAFT');
    }
  }
}
