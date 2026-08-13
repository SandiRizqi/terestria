import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/routing_service.dart';
import '../theme/app_theme.dart';

/// Mixin bersama untuk manajemen data routing OSM (import .pbf, hapus, dan
/// **tarik data jalan dari server per company**) + picker road tersimpan
/// offline. Dipakai oleh navigation & notification map agar keduanya identik:
/// perubahan/penambahan di sini otomatis ikut di kedua layar.
///
/// Host menyediakan lima kait: [routingService], [osmFilePath] (get/set),
/// [initRoutingEngine], dan [showRoutingSnack]. State [isImportingOsm] dimiliki
/// mixin dan boleh dibaca host untuk menampilkan overlay loading.
mixin RoutingDataManager<T extends StatefulWidget> on State<T> {
  // ─── Kait yang disediakan host ─────────────────────────────────────────────
  RoutingService get routingService;
  String? get osmFilePath;
  set osmFilePath(String? value);

  /// Bangun/rebuild engine routing (host mem-forward ke _initRouter miliknya).
  Future<void> initRoutingEngine({bool reinit = false});

  /// Tampilkan pesan singkat (host mem-forward ke snackbar miliknya).
  void showRoutingSnack(String message);

  // ─── State milik mixin ─────────────────────────────────────────────────────
  bool isImportingOsm = false;

  // ─── Import / delete file .pbf manual ──────────────────────────────────────

  Future<void> importOsmFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Select OSM file (.pbf / .osm)',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    final ext = path.split('.').last.toLowerCase();
    if (ext != 'pbf' && ext != 'osm') {
      showRoutingSnack('⚠️ Invalid file. Please select a .pbf or .osm file');
      return;
    }

    setState(() => isImportingOsm = true);
    final imported = await routingService.importOsmFile(path);
    if (!mounted) return;
    setState(() {
      isImportingOsm = false;
      osmFilePath = imported;
    });

    if (imported != null) {
      showRoutingSnack('✅ OSM data imported. Building routing engine...');
      initRoutingEngine(reinit: true);
    } else {
      showRoutingSnack('❌ Failed to import OSM file');
    }
  }

  Future<void> deleteOsmFile() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete OSM Data?'),
        content: const Text(
            'Routing data will be removed. You will need to re-import to use navigation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await routingService.deleteOsmFile();
    if (mounted) setState(() => osmFilePath = null);
    showRoutingSnack('🗑️ OSM data deleted');
  }

  // ─── Dialog / bottom sheet ─────────────────────────────────────────────────

  void showOsmMissingDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Routing Data Missing'),
        ]),
        content: const Text(
          'Navigation membutuhkan data jalan.\n\n'
          'Unduh langsung dari server (per company), atau import file .pbf manual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              showSavedRoadsPicker();
            },
            icon: const Icon(Icons.folder_open_rounded, size: 16),
            label: const Text('Tersimpan'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              downloadRoadsFromServer();
            },
            icon: const Icon(Icons.cloud_download_rounded, size: 16),
            label: const Text('Download'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGreen,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void showOsmManagementSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('OSM Routing Data',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Offline routing requires a .pbf file from OpenStreetMap.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              if (osmFilePath != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('File loaded',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green)),
                          Text(
                            osmFilePath!.split('/').last,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        importOsmFile();
                      },
                      icon: const Icon(Icons.file_open_rounded, size: 16),
                      label: const Text('Replace File'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryGreen),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        deleteOsmFile();
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Delete'),
                      style:
                          OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ),
                ]),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_rounded,
                        color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Belum ada data jalan. Unduh dari server atau import .pbf.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      downloadRoadsFromServer();
                    },
                    icon: const Icon(Icons.cloud_download_rounded, size: 16),
                    label: const Text('Download from Server'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      showSavedRoadsPicker();
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 16),
                    label: const Text('Road Tersimpan (Offline)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      importOsmFile();
                    },
                    icon: const Icon(Icons.file_open_rounded, size: 16),
                    label: const Text('Import .pbf File'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Tarik data jalan dari server (TR_ROAD per company) ────────────────────

  /// Alur: pilih company (dari scope) → unduh .osm.pbf → pasang ke GraphHopper
  /// hingga siap route. Company tanpa data → dialog "belum tersedia".
  Future<void> downloadRoadsFromServer() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final companies = await routingService.fetchDownloadableCompanies();
    if (!mounted) return;
    Navigator.pop(context);

    if (companies.isEmpty) {
      showRoutingSnack('⚠️ Tidak ada company yang tersedia untuk akun ini');
      return;
    }

    final downloaded =
        (await routingService.listDownloadedRoads()).map((d) => d.id).toSet();
    if (!mounted) return;
    final picked = await _showCompanyPicker(companies, downloaded);
    if (picked == null || !mounted) return;

    if (!picked.hasData) {
      _showRoadsUnavailableDialog();
      return;
    }

    final status = ValueNotifier<String>('Downloading road data…');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (_, v, __) => Text(v),
            ),
          ),
        ]),
      ),
    );

    final result = await routingService.downloadAndPrepareRoads(
      picked.id,
      name: picked.name,
      onProgress: (m) => status.value = m,
    );
    if (mounted) Navigator.pop(context);
    status.dispose();
    if (!mounted) return;

    switch (result.status) {
      case RoadPrepareStatus.ready:
        final path = await routingService.getOsmFilePath();
        if (mounted) setState(() => osmFilePath = path);
        showRoutingSnack('✅ ${result.message} (${picked.name})');
        break;
      case RoadPrepareStatus.empty:
        _showRoadsUnavailableDialog();
        break;
      case RoadPrepareStatus.error:
        showRoutingSnack('❌ ${result.message}');
        break;
    }
  }

  Future<DownloadableCompany?> _showCompanyPicker(
      List<DownloadableCompany> companies, Set<int> downloadedIds) {
    return showModalBottomSheet<DownloadableCompany>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Pilih Company',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: companies.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 16),
                itemBuilder: (_, i) {
                  final c = companies[i];
                  final isSaved = downloadedIds.contains(c.id);
                  return ListTile(
                    leading: Icon(Icons.alt_route_rounded,
                        color: c.hasData ? AppTheme.primaryGreen : Colors.grey),
                    title:
                        Text(c.name.isNotEmpty ? c.name : 'Company #${c.id}'),
                    subtitle: Text(c.hasData
                        ? '${c.roadCount} ruas jalan${isSaved ? ' • tersimpan' : ''}'
                        : 'Belum tersedia'),
                    trailing: !c.hasData
                        ? Text('—', style: TextStyle(color: Colors.grey.shade400))
                        : isSaved
                            ? const Chip(
                                label: Text('Update',
                                    style: TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(Icons.refresh_rounded, size: 14),
                              )
                            : const Icon(Icons.download_rounded, size: 20),
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showRoadsUnavailableDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Belum Tersedia'),
        ]),
        content: const Text(
            'Data jalan untuk company ini belum tersedia di server.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Pilih road data yang sudah tersimpan lokal (OFFLINE, tanpa unduh ulang).
  Future<void> showSavedRoadsPicker() async {
    final saved = await routingService.listDownloadedRoads();
    if (!mounted) return;
    if (saved.isEmpty) {
      showRoutingSnack(
          'Belum ada road data tersimpan. Download dulu dari server.');
      return;
    }

    final chosen = await showModalBottomSheet<DownloadedRoad>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Road Tersimpan (Offline)',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: saved.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16),
                    itemBuilder: (_, i) {
                      final d = saved[i];
                      final isActive = osmFilePath == d.path;
                      return ListTile(
                        leading: Icon(Icons.map_rounded,
                            color:
                                isActive ? AppTheme.primaryGreen : Colors.grey),
                        title: Text(d.name),
                        subtitle: isActive ? const Text('Sedang aktif') : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Colors.red),
                          tooltip: 'Hapus',
                          onPressed: () async {
                            await routingService.deleteDownloadedRoads(d.id);
                            saved.removeAt(i);
                            if (isActive && mounted) {
                              setState(() => osmFilePath = null);
                            }
                            setSheet(() {});
                            if (saved.isEmpty && ctx.mounted) Navigator.pop(ctx);
                          },
                        ),
                        onTap: () => Navigator.pop(ctx, d),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
    if (chosen == null || !mounted) return;

    final status = ValueNotifier<String>('Building routing engine…');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (_, v, __) => Text(v),
            ),
          ),
        ]),
      ),
    );
    final result = await routingService.activateDownloadedRoads(
      chosen.id,
      onProgress: (m) => status.value = m,
    );
    if (mounted) Navigator.pop(context);
    status.dispose();
    if (!mounted) return;

    if (result.status == RoadPrepareStatus.ready) {
      final path = await routingService.getOsmFilePath();
      if (mounted) setState(() => osmFilePath = path);
      showRoutingSnack('✅ ${result.message} (${chosen.name})');
    } else {
      showRoutingSnack('❌ ${result.message}');
    }
  }
}
