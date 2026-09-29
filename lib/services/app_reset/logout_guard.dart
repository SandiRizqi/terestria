import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/geo_data_model.dart';
import '../../models/project_model.dart';
import '../photo_sync_service.dart';
import '../storage_service.dart';
import '../tracking/tracking_session_manager.dart';

/// Data di HP yang akan hilang bila logout (logout = reset app ke kondisi
/// awal): belum tersinkron ke server, atau sesi tracking yang belum disimpan.
class PendingLogoutData {
  final int projects;
  final int geoData;
  final int photos;
  final int trackingSessions;

  const PendingLogoutData({
    this.projects = 0,
    this.geoData = 0,
    this.photos = 0,
    this.trackingSessions = 0,
  });

  bool get isEmpty =>
      projects == 0 && geoData == 0 && photos == 0 && trackingSessions == 0;

  @override
  String toString() => 'project=$projects data=$geoData foto=$photos '
      'sesi=$trackingSessions';
}

/// Hitung [PendingLogoutData]. Sumber data bisa disuntik (test); default
/// memakai StorageService + TrackingSessionManager milik app.
///
/// Jumlah project/data juga dihitung lewat COUNT SQL (bila sumber default):
/// baris yang tak bisa di-parse tetap terhitung, jadi tak ikut terhapus
/// diam-diam saat logout.
Future<PendingLogoutData> countPendingLogoutData({
  Future<List<Project>> Function()? unsyncedProjects,
  Future<List<GeoData>> Function()? unsyncedGeoData,
  Future<List<Project>> Function()? allProjects,
  int Function()? liveTrackingSessions,
  Future<int> Function()? unsyncedProjectCount,
  Future<int> Function()? unsyncedGeoDataCount,
}) async {
  final storage = StorageService();
  final projects =
      await (unsyncedProjects ?? storage.getUnsyncedProjects)();
  final geoData = await (unsyncedGeoData ?? storage.getUnsyncedGeoData)();
  final projectCount = unsyncedProjectCount != null
      ? await unsyncedProjectCount()
      : (unsyncedProjects == null
          ? await storage.getUnsyncedProjectCount()
          : projects.length);
  final geoDataCount = unsyncedGeoDataCount != null
      ? await unsyncedGeoDataCount()
      : (unsyncedGeoData == null
          ? await storage.getUnsyncedGeoDataCount()
          : geoData.length);
  final byId = {
    for (final p in await (allProjects ?? storage.loadProjects)()) p.id: p,
  };
  final photoSync = PhotoSyncService();
  var photos = 0;
  for (final g in geoData) {
    final project = byId[g.projectId];
    if (project == null) continue;
    photos += photoSync.pendingPhotoUploads(g.formData, project).length;
  }
  final sessions = (liveTrackingSessions ??
      () => TrackingSessionManager.instance.activeCount)();
  return PendingLogoutData(
    projects: math.max(projects.length, projectCount),
    geoData: math.max(geoData.length, geoDataCount),
    photos: photos,
    trackingSessions: sessions,
  );
}

enum LogoutChoice { cancel, sync, wipe }

/// Konfirmasi logout. Tanpa data tertunda: konfirmasi biasa yang menjelaskan
/// semua data di HP akan dihapus. Ada data tertunda: tampilkan jumlahnya +
/// **Sync dulu** / **Batal** / **Hapus & Logout** (wajib ketik `HAPUS`).
Future<LogoutChoice> showLogoutGuardDialog(
    BuildContext context, PendingLogoutData data) async {
  final choice = await showDialog<LogoutChoice>(
    context: context,
    builder: (_) => data.isEmpty
        ? const _PlainLogoutDialog()
        : _PendingLogoutDialog(data: data),
  );
  return choice ?? LogoutChoice.cancel;
}

const _wipeNote = 'Semua data aplikasi (project, data, foto, basemap, layer, '
    'cache peta, dan log) akan dihapus dari HP ini agar pengguna berikutnya '
    'mulai dari kondisi awal.';

class _PlainLogoutDialog extends StatelessWidget {
  const _PlainLogoutDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Logout'),
      content: const Text('$_wipeNote\n\nLanjutkan logout?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, LogoutChoice.cancel),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, LogoutChoice.wipe),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Logout'),
        ),
      ],
    );
  }
}

class _PendingLogoutDialog extends StatefulWidget {
  final PendingLogoutData data;
  const _PendingLogoutDialog({required this.data});

  @override
  State<_PendingLogoutDialog> createState() => _PendingLogoutDialogState();
}

class _PendingLogoutDialogState extends State<_PendingLogoutDialog> {
  final _confirm = TextEditingController();

  bool get _confirmed => _confirm.text.trim() == 'HAPUS';

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final items = [
      if (d.projects > 0) (Icons.folder_outlined, '${d.projects} project'),
      if (d.geoData > 0) (Icons.place_outlined, '${d.geoData} data'),
      if (d.photos > 0) (Icons.photo_outlined, '${d.photos} foto'),
      if (d.trackingSessions > 0)
        (Icons.route_outlined, '${d.trackingSessions} sesi tracking aktif'),
    ];
    return AlertDialog(
      icon: const Icon(Icons.warning_amber_rounded,
          color: Colors.orange, size: 36),
      title: const Text('Data belum tersinkron'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Data berikut belum ada di server dan akan HILANG bila '
                'logout sekarang:'),
            const SizedBox(height: 8),
            for (final (icon, label) in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Icon(icon, size: 18, color: Colors.red[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            if (d.trackingSessions > 0) ...[
              const SizedBox(height: 6),
              Text('Sesi tracking tidak ikut sync — simpan dulu dari panel '
                  'Tracking Aktif.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ],
            const SizedBox(height: 12),
            const Text(_wipeNote, style: TextStyle(fontSize: 12)),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Ketik HAPUS untuk logout tanpa sync',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, LogoutChoice.cancel),
          child: const Text('Batal'),
        ),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, LogoutChoice.sync),
          child: const Text('Sync dulu'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: _confirmed
              ? () => Navigator.pop(context, LogoutChoice.wipe)
              : null,
          child: const Text('Hapus & Logout'),
        ),
      ],
    );
  }
}
