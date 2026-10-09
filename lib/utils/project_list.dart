import '../models/project_model.dart';
import 'relative_time.dart';

/// Aturan daftar project (template "Projects list"): ringkasan data lokal per
/// project, filter All / Unsynced / From server, tag status sync, subjudul.

/// Ringkasan record project di HP.
class ProjectDataStats {
  final int total;
  final int unsynced;

  /// Record belum ter-upload yang push terakhirnya ditolak/gagal.
  final int failed;

  /// `updatedAt` record terbaru, atau null bila belum ada record.
  final DateTime? lastUpdated;

  const ProjectDataStats({
    required this.total,
    required this.unsynced,
    required this.failed,
    this.lastUpdated,
  });

  static const empty = ProjectDataStats(total: 0, unsynced: 0, failed: 0);
}

/// Hasil query terkelompok `geo_data` per project → ringkasan per project id.
Map<String, ProjectDataStats> projectDataStatsFromRows(
    List<Map<String, Object?>> rows) {
  int asInt(Object? v) => v is num ? v.toInt() : 0;
  return {
    for (final r in rows)
      r['projectId'] as String: ProjectDataStats(
        total: asInt(r['total']),
        unsynced: asInt(r['unsynced']),
        failed: asInt(r['failed']),
        lastUpdated: r['lastUpdated'] is num
            ? DateTime.fromMillisecondsSinceEpoch(
                (r['lastUpdated'] as num).toInt())
            : null,
      ),
  };
}

/// Project dibuat user lain → pasti diambil dari server. Tanpa pembuat atau
/// user belum diketahui → tidak dianggap dari server.
bool isFromServer(Project project, String? currentUsername) {
  final creator = project.createdBy?.trim().toLowerCase();
  final me = currentUsername?.trim().toLowerCase();
  if (creator == null || creator.isEmpty || me == null || me.isEmpty) {
    return false;
  }
  return creator != me;
}

/// Ada yang menunggu di-upload: project belum di server atau record lokal.
bool needsSync(Project project, ProjectDataStats stats) =>
    !project.isSynced || stats.unsynced > 0;

enum ProjectListFilter { all, unsynced, fromServer }

/// Cari (nama, deskripsi, pembuat; abaikan huruf besar/kecil) lalu filter chip.
List<Project> filterProjects(
  List<Project> projects, {
  required String query,
  required ProjectListFilter filter,
  required Map<String, ProjectDataStats> stats,
  required String? currentUsername,
}) {
  final q = query.trim().toLowerCase();
  return projects.where((p) {
    if (q.isNotEmpty &&
        !p.name.toLowerCase().contains(q) &&
        !p.description.toLowerCase().contains(q) &&
        !(p.createdBy?.toLowerCase().contains(q) ?? false)) {
      return false;
    }
    switch (filter) {
      case ProjectListFilter.all:
        return true;
      case ProjectListFilter.unsynced:
        return needsSync(p, stats[p.id] ?? ProjectDataStats.empty);
      case ProjectListFilter.fromServer:
        return isFromServer(p, currentUsername);
    }
  }).toList();
}

enum TagTone { neutral, success, warning, danger }

/// Tag status sync kartu project: gagal > belum ter-upload > project lokal >
/// tersinkron.
(String, TagTone) projectSyncTag(Project project, ProjectDataStats stats) {
  if (stats.failed > 0) return ('Sync failed', TagTone.danger);
  if (stats.unsynced > 0) return ('${stats.unsynced} unsynced', TagTone.warning);
  if (!project.isSynced) return ('Local', TagTone.warning);
  return ('Synced', TagTone.success);
}

/// "248 records · 2 h ago": aktivitas terakhir = ubah project atau record
/// terbaru, mana yang lebih baru.
String projectSubtitle(Project project, ProjectDataStats stats, DateTime now) {
  final last = stats.lastUpdated != null &&
          stats.lastUpdated!.isAfter(project.updatedAt)
      ? stats.lastUpdated!
      : project.updatedAt;
  final records =
      stats.total == 1 ? '1 record' : '${stats.total} records';
  return '$records · ${relativeTime(last, now)}';
}
