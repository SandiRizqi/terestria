import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:geoform_app/theme/app_theme.dart';
import '../../theme/light_app_bar.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import '../../models/project_model.dart';
import '../../models/geo_data_model.dart';
import '../../models/field_type_info.dart';
import '../../models/form_field_model.dart';
import '../../services/storage_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/sync_service.dart';
import '../../services/pull_preflight.dart';
import 'widgets/filter_option_chips.dart';
import 'widgets/pull_filter_sheet.dart';
import '../data_collection/data_collection_screen.dart';
import 'edit_geo_data_screen.dart';
import 'create_project_screen.dart';
import '../../widgets/geo_data_list_item.dart';
import '../../widgets/project/project_detail_header.dart';
import '../../widgets/project/geo_data_list_tile.dart';
import '../../widgets/project/selection_app_bar.dart';
import '../../widgets/project/local_delete_dialogs.dart';
import '../../utils/record_selection.dart';
import '../../services/data_view_mode_store.dart';
import '../../widgets/connectivity/connectivity_indicator.dart';
import 'dart:convert';
import 'dart:async';
import '../../services/auth_service.dart';
import '../../services/project_template_service.dart';
import 'package:file_picker/file_picker.dart';

import '../../utils/app_logger.dart';
import '../../utils/field_values.dart';
import '../../utils/record_title.dart';
import '../../utils/ui_feedback.dart';
import '../../services/export/geo_export.dart';
import '../../services/photo_sync_service.dart';
import '../../models/sync_conflict.dart';
import '../../widgets/sync/conflict_sheet.dart';
class ProjectDetailScreen extends StatefulWidget {
  final Project project;

  const ProjectDetailScreen({Key? key, required this.project}) : super(key: key);

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final StorageService _storageService = StorageService();
  final ConnectivityService _connectivityService = ConnectivityService();
  final SyncService _syncService = SyncService();
  
  List<GeoData> _geoDataList = [];
  List<GeoData> _filteredGeoDataList = [];
  bool _isLoading = true;
  late Project _currentProject;
  final TextEditingController _searchController = TextEditingController();
  bool _isOnline = false;
  StreamSubscription<bool>? _connectivitySubscription;
  bool _isSyncing = false;
  final ScrollController _scrollController = ScrollController();
  String _syncProgress = '';
  int _totalPhotosToProcess = 0;
  int _processedPhotos = 0;
  int _pendingPhotoCount = 0;
  String? _currentUsername;

  /// Grid (bawaan) atau list; pilihan disimpan di HP.
  DataViewMode _viewMode = DataViewMode.grid;

  // ── Mode pilih (tekan lama record / menu "Select records") ──
  bool _selectionMode = false;
  RecordSelection _selection = const RecordSelection();

  Iterable<String> get _visibleIds => _filteredGeoDataList.map((d) => d.id);

  // ── Filter state ──
  DateTimeRange? _dateFilter;
  Map<String, dynamic> _fieldFilters = {};

  /// True jika ada setidaknya satu filter aktif (date, field, atau search text).
  bool get _hasActiveFilters =>
      _dateFilter != null ||
      _fieldFilters.isNotEmpty ||
      _searchController.text.isNotEmpty;

  /// Jumlah filter aktif (hanya date + field, bukan search bar).
  int get _activeFilterCount =>
      (_dateFilter != null ? 1 : 0) + _fieldFilters.length;

  @override
  void initState() {
    super.initState();
    _currentProject = widget.project;
    _loadGeoData();
    _searchController.addListener(_applyFilters);
    _initConnectivity();
    _scrollController.addListener(_onScroll);
    _loadUsername();
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    final mode = await DataViewModeStore.load();
    if (mounted) setState(() => _viewMode = mode);
  }

  void _setViewMode(DataViewMode mode) {
    if (mode == _viewMode) return;
    setState(() => _viewMode = mode);
    DataViewModeStore.save(mode);
  }

  /// Masuk mode pilih; [first] langsung tercentang (tekan lama record).
  void _startSelection([GeoData? first]) {
    setState(() {
      _selectionMode = true;
      _selection = first == null
          ? const RecordSelection()
          : RecordSelection({first.id});
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selection = const RecordSelection();
    });
  }

  /// Ketuk record: di mode pilih mencentang/melepas, selain itu buka detail.
  void _onRecordTap(GeoData data) {
    if (_selectionMode) {
      setState(() => _selection = _selection.toggle(data.id));
    } else {
      _showDataDetail(data);
    }
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return SelectionAppBar(
      selectedCount: _selection.count,
      allSelected: _selection.allSelected(_visibleIds),
      onClose: _exitSelection,
      onToggleAll: () =>
          setState(() => _selection = _selection.toggleAll(_visibleIds)),
      actions: [
        IconButton(
          tooltip: 'Delete from this phone',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: _selection.isEmpty ? null : _deleteSelected,
        ),
      ],
    );
  }

  // ── Hapus dari HP saja (tidak ada penghapusan di server) ──

  /// Hapus saat sync berjalan bisa berebut dengan upload record yang sama.
  bool _blockedBySync() {
    if (!_isSyncing) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Wait until the sync finishes.')),
    );
    return true;
  }

  Future<void> _deleteSelected() async {
    if (_blockedBySync()) return;
    final records =
        _geoDataList.where((d) => _selection.contains(d.id)).toList();
    if (records.isEmpty) return;
    if (!await confirmDeleteSelected(context, records)) return;
    await _deleteLocally(records.map((r) => r.id).toList());
    if (mounted) _exitSelection();
  }

  Future<void> _clearLocalData() async {
    if (_blockedBySync()) return;
    final ids = await confirmClearLocalData(context, _geoDataList);
    if (ids == null || ids.isEmpty) return;
    await _deleteLocally(ids);
  }

  /// Satu transaksi DB: gagal di tengah → tidak ada yang terhapus.
  Future<void> _deleteLocally(List<String> ids) async {
    try {
      final n = await _storageService.deleteGeoDataBatch(ids);
      await _loadGeoData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${n == 1 ? '1 record' : '$n records'} deleted from this phone'),
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      showErrorFeedback(context, 'Could not delete the records',
          error: e, stack: st, tag: 'PROJECT');
    }
  }

  Future<void> _loadUsername() async {
    final authService = AuthService();
    final user = await authService.getUser();
    setState(() {
      _currentUsername = user?.username;
    });
    //print('👤 Current logged in user: $_currentUsername');
  }

  bool _canEditProject() {
    if (_currentUsername == null) return false;
    return _currentProject.createdBy == _currentUsername;
  }

  bool _canEditGeoData(GeoData data) {
    if (_currentUsername == null) {
      //print('❌ Cannot edit - No username loaded');
      return false;
    }

    // print(data);
    
    // Handle null collectedBy
    if (data.collectedBy == null) {
      //print('⚠️ Data has no collectedBy field - ID: ${data.id}');
      return false;
    }
    
    // Normalize untuk perbandingan (case-insensitive dan trim spaces)
    final normalizedDataUser = data.collectedBy!.trim().toLowerCase();
    final normalizedCurrentUser = _currentUsername!.trim().toLowerCase();
    
    final canEdit = normalizedDataUser == normalizedCurrentUser;
    //print('🔍 Permission check:');
    //print('   Data by: "${data.collectedBy}" (normalized: "$normalizedDataUser")');
    //print('   Current user: "$_currentUsername" (normalized: "$normalizedCurrentUser")');
    //print('   Can edit: $canEdit');
    
    return canEdit;
  }

  void _initConnectivity() {
    _connectivityService.startMonitoring();
    _isOnline = _connectivityService.isOnline;
    _connectivitySubscription = _connectivityService.connectivityStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
      }
    });
  }

  void _onScroll() {
    // Reserved for future scroll-based actions
  }

  Color _getGeoColor(String polygonType) {
    if (polygonType == 'POLYGON') {
      return AppTheme.polygonColor;
    }
    if (polygonType == 'LINE') {
      return AppTheme.lineColor;
    }
    if (polygonType == 'POINT') {
      return AppTheme.pointColor;
    }

    return Colors.grey;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _connectivitySubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Terapkan semua filter aktif secara AND:
  /// 1. Search text (formData values + tanggal)
  /// 2. Date range filter (_dateFilter)
  /// 3. Per-field filters (_fieldFilters)
  void _applyFilters() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      _filteredGeoDataList = _geoDataList.where((data) {
        // ── 1. Search text ──
        if (query.isNotEmpty) {
          final formDataMatch = data.formData.entries.any((entry) =>
              entry.value.toString().toLowerCase().contains(query));
          final dateMatch =
              _formatDate(data.createdAt).toLowerCase().contains(query);
          if (!formDataMatch && !dateMatch) return false;
        }

        // ── 2. Date range ──
        if (_dateFilter != null) {
          final start = DateTime(
            _dateFilter!.start.year,
            _dateFilter!.start.month,
            _dateFilter!.start.day,
          );
          final end = DateTime(
            _dateFilter!.end.year,
            _dateFilter!.end.month,
            _dateFilter!.end.day,
            23, 59, 59,
          );
          if (data.createdAt.isBefore(start) || data.createdAt.isAfter(end)) {
            return false;
          }
        }

        // ── 3. Per-field filters (aturan per tipe: fieldFilterMatches) ──
        for (final entry in _fieldFilters.entries) {
          final fieldDef = _currentProject.formFields
              .where((f) => f.label == entry.key)
              .firstOrNull;
          if (fieldDef == null) continue;
          if (!fieldFilterMatches(
              fieldDef, data.formData[entry.key], entry.value)) {
            return false;
          }
        }

        return true;
      }).toList();
      // Record yang tak terlihat lagi (filter berubah/terhapus) dilepas dari
      // pilihan, supaya aksi tidak mengenai record tersembunyi.
      _selection = _selection.retain(_visibleIds);
    });
  }

  /// Record project ini yang berkonflik dengan versi server (lihat banner).
  List<SyncConflict> _conflicts = const [];

  Future<void> _loadGeoData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await _storageService.loadGeoData(_currentProject.id);
      var conflicts = const <SyncConflict>[];
      try {
        conflicts =
            await _storageService.getSyncConflicts(projectId: _currentProject.id);
      } catch (e) {
        logWarn('Could not load sync conflicts: $e', tag: 'PROJECT');
      }
      // Foto yang belum ter-upload (antrean di kartu sync).
      var photos = 0;
      final photoSync = PhotoSyncService();
      for (final d in data) {
        if (d.isSynced) continue;
        photos += photoSync.pendingPhotoUploads(d.formData, _currentProject).length;
      }
      if (!mounted) return;
      setState(() {
        _geoDataList = data;
        _conflicts = conflicts;
        _pendingPhotoCount = photos;
        _isLoading = false;
      });
      // Terapkan ulang filter yang mungkin aktif setelah reload
      _applyFilters();
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorFeedback(context, 'Could not load the records',
          error: e, stack: st, tag: 'PROJECT');
    }
  }

  /// Record yang diubah di server & di HP: user memilih versi per record.
  Future<void> _openConflicts() async {
    final entries = [
      for (final c in _conflicts)
        ConflictEntry(
          conflict: c,
          local: _geoDataList.where((g) => g.id == c.geoDataId).firstOrNull,
        ),
    ];
    await showConflictResolutionSheet(
      context,
      project: _currentProject,
      entries: entries,
      keepMine: _syncService.resolveKeepMine,
      useServer: _syncService.resolveUseServer,
    );
    await _loadGeoData();
  }

  /// Buka sheet filter dinamis (key dari form_fields project) lalu jalankan
  /// preflight + pull. Menggantikan "pull all langsung": tiap pull kini wajib
  /// lewat cek koneksi → cek jumlah record → konfirmasi.
  Future<void> _openPullFilterSheet() async {
    if (_isSyncing || !_isOnline) return;

    // Kecualikan field foto: nilainya daftar file, tak bisa difilter teks.
    final keys = _currentProject.formFields
        .where((f) => f.type != FieldType.photo)
        .map((f) => f.label)
        .where((l) => l.trim().isNotEmpty)
        .toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => PullFilterSheet(
        fieldKeys: keys,
        onSubmit: (filters) {
          Navigator.of(ctx).pop();
          _pullWithFilters(filters);
        },
      ),
    );
  }

  /// Preflight: pastikan online → tanya jumlah record → konfirmasi (peringatan
  /// bila > ambang) → baru pull. Tidak ada jalur pull-all tanpa langkah ini.
  Future<void> _pullWithFilters(Map<String, String> filters) async {
    if (_isSyncing || !_isOnline) return;

    setState(() {
      _isSyncing = true;
      _syncProgress = 'Checking server...';
    });

    PullPreflightResult pre;
    try {
      pre = await _syncService.preflightPull(
        _currentProject.id,
        formDataFilters: filters,
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
    if (!mounted) return;

    switch (pre.status) {
      case PullPreflightStatus.offline:
      case PullPreflightStatus.error:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(pre.message ?? 'Could not check the server.'),
          backgroundColor: Colors.red,
        ));
        return;
      case PullPreflightStatus.empty:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No records on the server match this filter.'),
        ));
        return;
      case PullPreflightStatus.ready:
        break;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download data?'),
        content: Text(
          pre.warnLarge
              ? '${pre.count} records will be downloaded (more than 1000). This '
                  'can take a while and use a lot of data. Continue?'
              : '${pre.count} records will be downloaded. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _syncGeoDataFromServer(formDataFilters: filters);
    }
  }

  /// Pull manual: user memilih tanggal, hanya tarik record yang di-update setelah
  /// tanggal itu. TIDAK mengubah watermark delta (lihat pullGeoDataFromServer).
  Future<void> _pullSinceDate() async {
    if (_isSyncing || !_isOnline) return;

    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Pull data updated since',
    );
    if (picked == null) return;

    // Awal hari (lokal) tanggal terpilih; konversi ke UTC ditangani di service.
    await _syncGeoDataFromServer(
      updatedAfter: DateTime(picked.year, picked.month, picked.day),
    );
  }

  /// Sync GeoData untuk project ini dari server.
  ///
  /// [forceFull] true → abaikan watermark delta (tarik semua record project),
  /// dipakai untuk pull-to-refresh manual / pemulihan bila data terasa desync.
  Future<void> _syncGeoDataFromServer({
    bool forceFull = false,
    DateTime? updatedAfter,
    Map<String, String>? formDataFilters,
  }) async {
    if (_isSyncing || !_isOnline) return;

    setState(() {
      _isSyncing = true;
      _syncProgress = 'Fetching data from server...';
    });

    try {
      final result = await _syncService.pullGeoDataFromServer(
        _currentProject.id,
        forceFull: forceFull,
        updatedAfter: updatedAfter,
        formDataFilters: formDataFilters,
        onProgress: (message) {
          if (mounted) {
            setState(() => _syncProgress = message);
          }
        },
      );

      if (mounted && result.success) {
        final newCount = result.data?['saved'] as int? ?? 0;
        final updatedCount = result.data?['updated'] as int? ?? 0;

        if (newCount > 0 || updatedCount > 0) {
          String message = '';
          if (newCount > 0) message += '$newCount new';
          if (updatedCount > 0) {
            if (message.isNotEmpty) message += ', ';
            message += '$updatedCount updated';
          }
          message += ' geodata synced';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.cloud_download, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(child: Text(message)),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else if (mounted && !result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Sync error: ${result.message}')),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      logWarn('Error syncing geodata from server: $e', tag: 'PROJECT');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(loggedErrorMessage('Download from the server failed', e, tag: 'SYNC'))),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // PENTING: Reload data di finally block SEBELUM mengubah _isSyncing
      // Beri waktu untuk memastikan file sudah tersimpan ke disk
      await Future.delayed(const Duration(milliseconds: 150));
      await _loadGeoData();

      if (mounted) {
        setState(() {
          _isSyncing = false;
          _syncProgress = '';
        });
      }
    }
  }


  /// Tampilkan bottom sheet pilihan format export (GeoJSON / CSV).
  Future<void> _exportData() async {
    final exportCount = _filteredGeoDataList.length;
    final isFiltered = _hasActiveFilters;

    if (_geoDataList.isEmpty) {
      if (mounted) {
        showInfoFeedback(context, 'There is no data to export yet.',
            warning: true);
      }
      return;
    }

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).padding.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              const Text(
                'Export Data',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                isFiltered
                    ? '$exportCount records (current filter)'
                    : '$exportCount records (all data)',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Pilihan GeoJSON
              _buildExportOption(
                icon: Icons.location_on_rounded,
                iconColor: Colors.blue.shade700,
                title: 'GeoJSON',
                subtitle: 'Standard GIS format — opens in QGIS, ArcGIS, etc.',
                onTap: () {
                  Navigator.pop(ctx);
                  _doExportGeoJSON();
                },
              ),

              const SizedBox(height: 10),

              // Pilihan CSV
              _buildExportOption(
                icon: Icons.table_chart_rounded,
                iconColor: Colors.green.shade700,
                title: 'CSV',
                subtitle: 'Table — opens in Excel, Google Sheets, etc.',
                onTap: () {
                  Navigator.pop(ctx);
                  _doExportCSV();
                },
              ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExportOption({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey.shade400, size: 20),
          ],
        ),
      ),
    );
  }

  /// Simpan hasil ekspor lewat dialog file sistem. `false` bila dibatalkan.
  Future<bool> _saveExportFile({
    required String content,
    required String extension,
    required List<String> allowedExtensions,
    required String dialogTitle,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final projectName = _currentProject.name
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(' ', '_');
    final fileName = '${projectName}_$timestamp.$extension';

    if (Platform.isAndroid || Platform.isIOS) {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      return path != null;
    }
    var path = await FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (path == null) return false;
    final lower = path.toLowerCase();
    if (!allowedExtensions.any((e) => lower.endsWith('.$e'))) {
      path += '.$extension';
    }
    await File(path).writeAsString(content, flush: true);
    return true;
  }

  /// Export GeoJSON (ikut filter aktif). Record tanpa geometri valid
  /// dilewati & dilaporkan — dulu diekspor ke [0,0] ("Null Island").
  Future<void> _doExportGeoJSON() async {
    final records = List<GeoData>.of(_filteredGeoDataList);
    final project = _currentProject;
    try {
      // Encode di isolate: ribuan titik track bisa membekukan UI.
      final (json, features, skipped) = await compute(_encodeGeoJsonExport,
          (project: project, records: records));
      if (!mounted) return;
      if (features == 0) {
        showInfoFeedback(
            context,
            'Nothing to export: none of the ${records.length} records has '
            'a valid geometry.',
            warning: true);
        return;
      }
      final saved = await _saveExportFile(
        content: json,
        extension: 'geojson',
        allowedExtensions: const ['geojson', 'json'],
        dialogTitle: 'Save GeoJSON',
      );
      if (!saved) return;
      logInfo(
          'Exported GeoJSON "${project.name}": $features features'
          '${skipped.isEmpty ? '' : ', skipped ${skipped.length} without '
              'geometry: ${skipped.take(10).join(', ')}'}',
          tag: 'EXPORT');
      if (!mounted) return;
      showInfoFeedback(
        context,
        skipped.isEmpty
            ? 'GeoJSON saved — $features features'
            : 'GeoJSON saved — $features features. ${skipped.length} '
                'record(s) without a valid geometry were skipped.',
        success: skipped.isEmpty,
        warning: skipped.isNotEmpty,
      );
    } catch (e, st) {
      if (mounted) {
        showErrorFeedback(context, 'Could not export GeoJSON',
            error: e, stack: st, tag: 'EXPORT');
      }
    }
  }

  /// Export CSV (ikut filter aktif).
  Future<void> _doExportCSV() async {
    final records = List<GeoData>.of(_filteredGeoDataList);
    final project = _currentProject;
    try {
      final csv = await compute(
          _encodeCsvExport, (project: project, records: records));
      final saved = await _saveExportFile(
        content: csv,
        extension: 'csv',
        allowedExtensions: const ['csv'],
        dialogTitle: 'Save CSV',
      );
      if (!saved) return;
      logInfo('Exported CSV "${project.name}": ${records.length} rows',
          tag: 'EXPORT');
      if (!mounted) return;
      showInfoFeedback(context, 'CSV saved — ${records.length} rows',
          success: true);
    } catch (e, st) {
      if (mounted) {
        showErrorFeedback(context, 'Could not export CSV',
            error: e, stack: st, tag: 'EXPORT');
      }
    }
  }

  /// Sinkron satu tombol: project (bila belum ada di server) → record → foto.
  /// Memakai [SyncService.syncProjectAndData] yang eksklusif sehingga tak
  /// pernah bentrok dengan auto-sync. [onlyIds] dipakai "Retry failed".
  Future<void> _syncNow({Set<String>? onlyIds}) async {
    if (_isSyncing) return;
    if (!_isOnline) {
      showInfoFeedback(
          context,
          'No internet connection. Your data is safe on this phone — sync '
          'when you are online.',
          warning: true);
      return;
    }
    final pending =
        onlyIds?.length ?? _geoDataList.where((d) => !d.isSynced).length;
    if (pending == 0 && _currentProject.isSynced) {
      showInfoFeedback(context, 'Everything is already synced.',
          success: true);
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncProgress = _syncService.isSyncing.value
          ? 'Waiting for the background sync to finish…'
          : 'Preparing…';
    });
    logInfo(
        'Sync "${_currentProject.name}": $pending record(s)'
        '${onlyIds != null ? ' (retry failed)' : ''}'
        '${_currentProject.isSynced ? '' : ' + project'}',
        tag: 'SYNC');

    BatchSyncResult? result;
    try {
      result = await _syncService.syncProjectAndData(
        _currentProject,
        onlyIds: onlyIds,
        onProgress: (message, {done, total}) {
          if (mounted) setState(() => _syncProgress = message);
        },
      );
    } catch (e, st) {
      if (mounted) {
        showErrorFeedback(context, 'Sync failed',
            error: e, stack: st, tag: 'SYNC');
      }
    }

    // Storage = satu-satunya sumber kebenaran status sync.
    final refreshed = await _storageService.getProjectById(_currentProject.id);
    await _loadGeoData();
    if (!mounted) return;
    setState(() {
      if (refreshed != null) _currentProject = refreshed;
      _isSyncing = false;
      _syncProgress = '';
    });
    if (result != null) _showSyncResult(result);
  }

  /// Ringkasan hasil sync dengan bahasa manusia + "Retry failed".
  void _showSyncResult(BatchSyncResult r) {
    logInfo(
        'Sync result "${_currentProject.name}": ${r.successCount}/${r.total} '
        'uploaded, failed=${r.failedIds.length}, projectFailed=${r.projectFailed}, '
        'offline=${r.abortedDueToConnection}, auth=${r.abortedDueToAuth}',
        tag: 'SYNC');
    if (r.abortedDueToAuth) {
      showInfoFeedback(
        context,
        'Your session expired — sign in again, then tap Sync.',
        warning: true,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Sign in',
          onPressed: AuthService().requestReLogin,
        ),
      );
      return;
    }
    if (r.abortedDueToConnection) {
      showInfoFeedback(
        context,
        '${r.successCount} uploaded, ${r.failedIds.length} still waiting. The '
        'server could not be reached — your data is safe on this phone.',
        warning: true,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _syncNow(
              onlyIds: r.failedIds.isEmpty ? null : r.failedIds.toSet()),
        ),
      );
      return;
    }
    if (!r.hasErrors && !r.projectFailed) {
      showInfoFeedback(
          context,
          r.total == 0
              ? 'Project is on the server now.'
              : 'All ${r.total} record${r.total == 1 ? '' : 's'} uploaded.',
          success: true);
      return;
    }

    final grouped = SyncService.groupErrors(r.errors);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cloud_off_rounded,
            color: Colors.orange, size: 32),
        title: Text(r.projectFailed
            ? 'Project could not be uploaded'
            : r.successCount > 0
                ? 'Some records were not uploaded'
                : 'Nothing was uploaded'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.projectFailed
                  ? 'The project has to be on the server before its records '
                      'can be uploaded. Your data is safe on this phone.'
                  : '${r.successCount} of ${r.total} records uploaded. The '
                      'rest stay safely on this phone.'),
              if (grouped.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Reasons:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...grouped.take(5).map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $e', style: const TextStyle(fontSize: 13)),
                    )),
                if (grouped.length > 5)
                  Text('…and ${grouped.length - 5} more',
                      style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _syncNow(
                  onlyIds: r.projectFailed || r.failedIds.isEmpty
                      ? null
                      : r.failedIds.toSet());
            },
            child: const Text('Retry failed'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGeoData(GeoData data) async {
    // Validasi akses delete
    if (!_canEditGeoData(data)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.lock, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('You can only delete data you collected'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete record?'),
        content: Text(data.isSynced
            ? 'This record is already on the server. Deleting it here only '
                'removes it from this device — it stays on the server and can '
                'come back after a full download. Ask an administrator to '
                'delete it on the server.'
            : 'This record has not been uploaded yet. Deleting it removes it '
                'permanently.'),
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

    if (confirm == true) {
      try {
        await _storageService.deleteGeoData(data.id);
        _loadGeoData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Data deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(loggedErrorMessage('Could not delete the record', e, tag: 'PROJECT'))),
          );
        }
      }
    }
  }

  Future<void> _editGeoData(GeoData data) async {
    // Validasi akses edit
    if (!_canEditGeoData(data)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.lock, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('You can only edit data you collected'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditGeoDataScreen(
          geoData: data,
          project: _currentProject,
        ),
      ),
    );

    // Reload data jika ada perubahan
    if (result == true) {
      await _loadGeoData();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Back di mode pilih = keluar dari mode pilih, bukan meninggalkan layar.
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSelection();
      },
      child: Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      // Bar terang seperti template; judul project & pencarian ada di badan
      // halaman (_buildHeader).
      appBar: _selectionMode ? _buildSelectionAppBar() : lightAppBar(
        titleSpacing: 0,
        title: const Align(
          alignment: Alignment.centerLeft,
          child: ConnectivityIndicator(
            showLabel: true,
            iconSize: 16,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Export data',
            icon: const Icon(Icons.download_rounded),
            onPressed: _exportData,
          ),
          PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          ),
          elevation: 8,
          offset: const Offset(0, 50),
          itemBuilder: (context) => [
          // Edit Project - hanya tampil jika user adalah creator
              
              //if (_canEditProject())
              PopupMenuItem<String>(
                value: 'pull_from_server',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.cloud_download_rounded,
                        color: Colors.green,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pull with Filter',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Filter fields, check count, then download',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'pull_since_date',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.event_rounded,
                        color: Colors.teal,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pull Since Date',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Download data updated after a date',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'sync_to_server',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.cloud_upload_rounded,
                        color: Theme.of(context).primaryColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Push to Server',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Upload geodata to cloud',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'info',
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: Colors.blue,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Project Info',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'View project details',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'clear_local',
                enabled: _geoDataList.isNotEmpty,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.cleaning_services_outlined,
                        color: AppTheme.errorColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Clear Local Data',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: AppTheme.errorColor,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Remove records from this phone only',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'pull_from_server') {
                _openPullFilterSheet();
              } else if (value == 'pull_since_date') {
                _pullSinceDate();
              } else if (value == 'sync_to_server') {
                _syncNow();
              } else if (value == 'info') {
                _showProjectInfo();
              } else if (value == 'clear_local') {
                _clearLocalData();
              }
            },
          ),
        ],
      ),
      // Header (judul, statistik, banner, cari/filter) tetap di atas; hanya
      // daftar data yang bergulir. Bawah tidak dipotong SafeArea: daftar
      // bergulir sampai tepi layar, padding bawahnya memberi ruang FAB +
      // bilah navigasi HP (tanpa pita kosong di bawah).
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildHeader(),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                // Pull-to-refresh = muat ulang data LOKAL saja. Pull dari
                // server hanya lewat "Pull with Filter" / "Pull Since Date".
                onRefresh: _loadGeoData,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: _buildDataSlivers(),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectionMode ? null : FloatingActionButton.extended(
        onPressed: _navigateToDataCollection,
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add Data', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      ),
    );
  }

  /// Header halaman (template "Project detail · data"): judul, statistik,
  /// status sync/konflik, cari + filter, jumlah record + grid/list.
  List<Widget> _buildHeader() {
    final unsyncedCount = _geoDataList.where((data) => !data.isSynced).length;
    return [
      ProjectDetailTitle(
        name: _currentProject.name,
        createdBy: _currentProject.createdBy,
        updatedAt: _currentProject.updatedAt,
      ),
      const SizedBox(height: 10),
      ProjectStatsRow(
        type: _geometryLabel(),
        records: _geoDataList.length,
        fields: _currentProject.formFields.length,
      ),
      if (_isSyncing) ...[
        const SizedBox(height: 8),
        _buildSyncProgress(),
      ],
      // Antrean sync + satu tombol (project → record → foto sekaligus).
      if (!_currentProject.isSynced || unsyncedCount > 0) ...[
        const SizedBox(height: 8),
        SyncPendingBanner(
          unsyncedCount: unsyncedCount,
          pendingPhotoCount: _pendingPhotoCount,
          projectSynced: _currentProject.isSynced,
          isOnline: _isOnline,
          isSyncing: _isSyncing,
          onSync: _syncNow,
        ),
      ],
      // Record yang diubah di server & di HP → user memilih versi.
      if (_conflicts.isNotEmpty) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: ConflictBanner(
            count: _conflicts.length,
            onResolve: _openConflicts,
          ),
        ),
      ],
      const SizedBox(height: 10),
      DataSearchBar(
        controller: _searchController,
        activeFilterCount: _activeFilterCount,
        onOpenFilters: _showFilterPanel,
      ),
      const SizedBox(height: 4),
      RecordsHeaderRow(
        visibleCount: _filteredGeoDataList.length,
        totalCount: _geoDataList.length,
        hasActiveFilters: _hasActiveFilters,
        onClearFilters: _clearAllFilters,
        viewMode: _viewMode,
        onViewModeChanged: _setViewMode,
        selectionMode: _selectionMode,
        onToggleSelection: _selectionMode
            ? _exitSelection
            : (_filteredGeoDataList.isEmpty ? null : _startSelection),
      ),
    ];
  }

  String _geometryLabel() {
    switch (_currentProject.geometryType) {
      case GeometryType.point:
        return 'Point';
      case GeometryType.line:
        return 'Line';
      case GeometryType.polygon:
        return 'Polygon';
    }
  }

  Widget _buildSyncProgress() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _syncProgress.isEmpty ? 'Syncing with server...' : _syncProgress,
              style: TextStyle(
                fontSize: 13,
                color: Colors.blue[800],
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _clearAllFilters() {
    setState(() {
      _dateFilter = null;
      _fieldFilters = {};
    });
    _searchController.clear(); // listener → _applyFilters
    _applyFilters();
  }

  /// Daftar data sebagai sliver: memuat / kosong / tanpa hasil / grid / list.
  List<Widget> _buildDataSlivers() {
    Widget fill(Widget child) =>
        SliverFillRemaining(hasScrollBody: false, child: child);
    if (_isLoading) {
      return [fill(const Center(child: CircularProgressIndicator()))];
    }
    if (_geoDataList.isEmpty) return [fill(_buildEmptyState())];
    if (_filteredGeoDataList.isEmpty) return [fill(_buildNoResultsState())];
    return [
      _viewMode == DataViewMode.list ? _buildDataList() : _buildDataGrid(),
    ];
  }

  /// Ruang di bawah data terakhir: FAB + bilah navigasi HP (body tidak
  /// dipotong SafeArea bawah).
  double get _listBottomPadding => 96 + MediaQuery.paddingOf(context).bottom;

  Widget _buildDataGrid() {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, _listBottomPadding),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.70, // Memberikan ruang vertikal lebih lega
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _filteredGeoDataList.length,
        itemBuilder: (context, index) {
          final data = _filteredGeoDataList[index];
          final canEdit = _canEditGeoData(data);
          return GeoDataListItem(
            geoData: data,
            geometryType: _currentProject.geometryType,
            project: _currentProject,
            onDelete: canEdit ? () => _deleteGeoData(data) : null,
            onEdit: canEdit ? () => _editGeoData(data) : null,
            onTap: () => _onRecordTap(data),
            onLongPress: _selectionMode ? null : () => _startSelection(data),
            selectionMode: _selectionMode,
            selected: _selection.contains(data.id),
          );
        },
      ),
    );
  }

  /// Tampilan list (template "Project detail · data"): satu baris per record.
  Widget _buildDataList() {
    return SliverPadding(
      padding: EdgeInsets.only(top: 4, bottom: _listBottomPadding),
      sliver: SliverList.separated(
        itemCount: _filteredGeoDataList.length,
        separatorBuilder: (context, index) =>
            Divider(height: 1, indent: 72, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final data = _filteredGeoDataList[index];
          final canEdit = _canEditGeoData(data);
          return GeoDataListTile(
            geoData: data,
            project: _currentProject,
            currentUsername: _currentUsername,
            onTap: () => _onRecordTap(data),
            onLongPress: _selectionMode ? null : () => _startSelection(data),
            selectionMode: _selectionMode,
            selected: _selection.contains(data.id),
            onEdit: canEdit ? () => _editGeoData(data) : null,
            onDelete: canEdit ? () => _deleteGeoData(data) : null,
          );
        },
      ),
    );
  }

  IconData _getGeometryIconForType() {
    switch (_currentProject.geometryType) {
      case GeometryType.point:
        return Icons.place_rounded;
      case GeometryType.line:
        return Icons.timeline_rounded;
      case GeometryType.polygon:
        return Icons.pentagon_outlined;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.location_off,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Data Collected Yet',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start collecting geospatial data for this project',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 100,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No Results Found',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  void _navigateToDataCollection() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DataCollectionScreen(project: _currentProject),
      ),
    );

    // Selalu reload — edit/delete dari map juga mengubah local data
    await _loadGeoData();

    // Scroll ke atas hanya jika ada data baru yang ditambahkan
    if (result == true && _geoDataList.isNotEmpty && _scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showFilterPanel() {
    // Buat salinan lokal supaya user bisa cancel tanpa mengubah state asli
    DateTimeRange? localDateFilter = _dateFilter;
    final Map<String, dynamic> localFieldFilters = Map.from(_fieldFilters);

    // Controller untuk field yang difilter dengan teks
    final Map<String, TextEditingController> textControllers = {};
    for (final field in _currentProject.formFields) {
      if (fieldFilterKind(field.type) == FieldFilterKind.text) {
        textControllers[field.label] = TextEditingController(
          text: localFieldFilters[field.label]?.toString() ?? '',
        );
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.tune_rounded, size: 20, color: AppTheme.primaryGreen),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Filter Data',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        // Hapus semua
                        TextButton(
                          onPressed: () {
                            setSheetState(() {
                              localDateFilter = null;
                              localFieldFilters.clear();
                              for (final c in textControllers.values) {
                                c.clear();
                              }
                            });
                          },
                          child: const Text(
                            'Clear all',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // Scrollable content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Date Range Filter ──
                          _buildFilterSectionLabel(
                            icon: Icons.calendar_today_rounded,
                            label: 'Collection date',
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDatePickerTile(
                                  label: 'From',
                                  date: localDateFilter?.start,
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: localDateFilter?.start ?? DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );
                                    if (picked != null) {
                                      setSheetState(() {
                                        localDateFilter = DateTimeRange(
                                          start: picked,
                                          end: localDateFilter?.end ??
                                              DateTime.now(),
                                        );
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildDatePickerTile(
                                  label: 'To',
                                  date: localDateFilter?.end,
                                  onTap: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: localDateFilter?.end ?? DateTime.now(),
                                      firstDate: localDateFilter?.start ?? DateTime(2020),
                                      lastDate: DateTime.now(),
                                    );
                                    if (picked != null) {
                                      setSheetState(() {
                                        localDateFilter = DateTimeRange(
                                          start: localDateFilter?.start ?? DateTime(2020),
                                          end: picked,
                                        );
                                      });
                                    }
                                  },
                                ),
                              ),
                              if (localDateFilter != null) ...[
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.red),
                                  onPressed: () => setSheetState(() => localDateFilter = null),
                                  tooltip: 'Clear date filter',
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ],
                          ),

                          // ── Per-field filters ──
                          ...() {
                            final filterableFields = _currentProject.formFields
                                .where((f) =>
                                    fieldFilterKind(f.type) != FieldFilterKind.none)
                                .toList();

                            if (filterableFields.isEmpty) return <Widget>[];

                            return filterableFields.map((field) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 18),
                                  _buildFilterSectionLabel(
                                    icon: _getFieldIcon(field),
                                    label: field.label,
                                  ),
                                  const SizedBox(height: 10),

                                  // UI berdasarkan jenis filter tipe field
                                  if (fieldFilterKind(field.type) ==
                                      FieldFilterKind.text)
                                    TextField(
                                      controller: textControllers[field.label],
                                      keyboardType: field.type == FieldType.number ||
                                              field.type == FieldType.decimal
                                          ? const TextInputType.numberWithOptions(decimal: true)
                                          : TextInputType.text,
                                      onChanged: (v) => localFieldFilters[field.label] = v,
                                      decoration: InputDecoration(
                                        hintText: 'Search in "${field.label}"…',
                                        hintStyle: const TextStyle(fontSize: 13),
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: Colors.grey.shade300),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: BorderSide(color: Colors.grey.shade300),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: AppTheme.primaryGreen, width: 2),
                                        ),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        suffixIcon: (localFieldFilters[field.label] ?? '').isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(Icons.close_rounded, size: 16),
                                                onPressed: () {
                                                  setSheetState(() {
                                                    textControllers[field.label]?.clear();
                                                    localFieldFilters.remove(field.label);
                                                  });
                                                },
                                              )
                                            : null,
                                      ),
                                    )

                                  else if (fieldFilterKind(field.type) ==
                                          FieldFilterKind.choice &&
                                      (field.options ?? const []).isNotEmpty)
                                    // Dropdown: sama persis; pilihan ganda:
                                    // record yang memuat opsi ini.
                                    FilterOptionChips(
                                      values: field.options!,
                                      selected: localFieldFilters[field.label]
                                          ?.toString(),
                                      onChanged: (v) => setSheetState(() {
                                        if (v == null) {
                                          localFieldFilters.remove(field.label);
                                        } else {
                                          localFieldFilters[field.label] = v;
                                        }
                                      }),
                                    )

                                  else if (field.type == FieldType.rating)
                                    FilterOptionChips(
                                      values: const ['1', '2', '3', '4', '5'],
                                      labelOf: (v) => '$v ★',
                                      selected: localFieldFilters[field.label]
                                          ?.toString(),
                                      onChanged: (v) => setSheetState(() {
                                        if (v == null) {
                                          localFieldFilters.remove(field.label);
                                        } else {
                                          localFieldFilters[field.label] = v;
                                        }
                                      }),
                                    )

                                  else if (field.type == FieldType.checkbox)
                                    Row(
                                      children: ['', 'true', 'false'].map((val) {
                                        final labels = {
                                          '': 'All',
                                          'true': 'Yes ✓',
                                          'false': 'No ✗',
                                        };
                                        final current =
                                            (localFieldFilters[field.label] ?? '').toString();
                                        final isSelected = current == val;
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: GestureDetector(
                                            onTap: () {
                                              setSheetState(() {
                                                if (val.isEmpty) {
                                                  localFieldFilters.remove(field.label);
                                                } else {
                                                  localFieldFilters[field.label] = val;
                                                }
                                              });
                                            },
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 150),
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 16, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? AppTheme.primaryGreen
                                                    : Colors.grey.shade100,
                                                borderRadius: BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? AppTheme.primaryGreen
                                                      : Colors.grey.shade300,
                                                ),
                                              ),
                                              child: Text(
                                                labels[val]!,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : AppTheme.textPrimary,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    )

                                  else if (field.type == FieldType.date)
                                    _buildDatePickerTile(
                                      label: 'Pick a date',
                                      date: localFieldFilters[field.label] != null
                                          ? DateTime.tryParse(
                                              localFieldFilters[field.label].toString())
                                          : null,
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: DateTime.now(),
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now(),
                                        );
                                        if (picked != null) {
                                          setSheetState(() {
                                            localFieldFilters[field.label] =
                                                picked.toIso8601String().split('T').first;
                                          });
                                        }
                                      },
                                    ),
                                ],
                              );
                            }).toList();
                          }(),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // Footer — Terapkan & Batal
                  Container(
                    padding: EdgeInsets.fromLTRB(
                        16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(top: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              // Dispose text controllers
                              for (final c in textControllers.values) {
                                c.dispose();
                              }
                              // Bersihkan filter field yang kosong
                              localFieldFilters.removeWhere(
                                  (k, v) => v == null || v.toString().isEmpty);
                              // Terapkan ke state utama
                              setState(() {
                                _dateFilter = localDateFilter;
                                _fieldFilters = localFieldFilters;
                              });
                              _applyFilters();
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Apply filters',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // Pastikan controllers ter-dispose jika user swipe dismiss.
      // Dispose tanpa cek hasListeners (member protected & controller tetap
      // perlu di-dispose walau tanpa listener). try/catch menjaga dari
      // double-dispose.
      for (final c in textControllers.values) {
        try { c.dispose(); } catch (_) {}
      }
    });
  }

  /// Label section di filter panel
  Widget _buildFilterSectionLabel({required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppTheme.primaryGreen),
        const SizedBox(width: 7),
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  /// Tile tombol date picker yang reusable
  Widget _buildDatePickerTile({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    final formatted = date != null
        ? '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}'
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: date != null
              ? AppTheme.primaryGreen.withOpacity(0.06)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: date != null
                ? AppTheme.primaryGreen.withOpacity(0.4)
                : Colors.grey.shade300,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 14,
              color: date != null ? AppTheme.primaryGreen : Colors.grey.shade500,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                formatted ?? label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: date != null ? FontWeight.w600 : FontWeight.w400,
                  color: date != null ? AppTheme.primaryGreen : Colors.grey.shade500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showProjectInfo() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with gradient
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getGeometryIconForType(),
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Project Info',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentProject.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Description Section
                      _buildInfoSection(
                        icon: Icons.description_outlined,
                        iconColor: Colors.blue,
                        title: 'Description',
                        child: Text(
                          _currentProject.description.isNotEmpty 
                              ? _currentProject.description 
                              : 'No description provided',
                          style: TextStyle(
                            fontSize: 14,
                            color: _currentProject.description.isNotEmpty 
                                ? const Color(0xFF374151) 
                                : Colors.grey[500],
                            height: 1.5,
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Geometry Type Section
                      _buildInfoSection(
                        icon: _getGeometryIconForType(),
                        iconColor: _getGeoColor(_currentProject.geometryType.toString().split('.').last.toUpperCase()),
                        title: 'Geometry Type',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _getGeoColor(_currentProject.geometryType.toString().split('.').last.toUpperCase()).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getGeoColor(_currentProject.geometryType.toString().split('.').last.toUpperCase()).withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            _currentProject.geometryType.toString().split('.').last.toUpperCase(),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _getGeoColor(_currentProject.geometryType.toString().split('.').last.toUpperCase()),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Creator Section (if available)
                      if (_currentProject.createdBy != null) ...[
                        _buildInfoSection(
                          icon: Icons.person_outline,
                          iconColor: Colors.purple,
                          title: 'Created By',
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Colors.purple[700],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _currentProject.createdBy!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF374151),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      
                      // Form Fields Section
                      _buildInfoSection(
                        icon: Icons.view_list_outlined,
                        iconColor: Colors.orange,
                        title: 'Form Fields',
                        subtitle: '${_currentProject.formFields.length} field${_currentProject.formFields.length > 1 ? "s" : ""}',
                        child: _currentProject.formFields.isEmpty
                            ? Text(
                                'No form fields defined',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            : Column(
                                children: _currentProject.formFields.map((field) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[50],
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Colors.grey[200]!),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          _getFieldIcon(field),
                                          size: 18,
                                          color: Colors.orange[700],
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                field.label,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF374151),
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _getFieldTypeName(field),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (field.required)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.red[50],
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Required',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.red[700],
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Metadata Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.grey[100]!,
                              Colors.grey[50]!,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Column(
                          children: [
                            _buildMetadataRow(
                              icon: Icons.calendar_today_outlined,
                              label: 'Created',
                              value: _formatDate(_currentProject.createdAt),
                              iconColor: Colors.green,
                            ),
                            if (_currentProject.updatedAt != _currentProject.createdAt) ...[
                              const SizedBox(height: 12),
                              _buildMetadataRow(
                                icon: Icons.update_outlined,
                                label: 'Updated',
                                value: _formatDate(_currentProject.updatedAt),
                                iconColor: Colors.blue,
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetadataRow(
                                    icon: Icons.fingerprint_outlined,
                                    label: 'Project ID',
                                    value: _currentProject.id.substring(0, 8) + '...',
                                    iconColor: Colors.grey,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy_rounded, size: 20, color: Colors.blue),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: _currentProject.id));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Project ID copied to clipboard'),
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                                  tooltip: 'Copy Project ID',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Footer Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(
                    top: BorderSide(color: Colors.grey[200]!),
                  ),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _exportProjectTemplate();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.file_download, size: 18),
                      label: const Text(
                        'Export Template',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildInfoSection({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                size: 18,
                color: iconColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
  
  Widget _buildMetadataRow({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: iconColor,
        ),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
  
  IconData _getFieldIcon(FormFieldModel field) =>
      field.isUnknownType ? Icons.help_outline : fieldTypeInfo(field.type).icon;

  String _getFieldTypeName(FormFieldModel field) {
    return fieldTypeDisplayName(field);
  }

  void _showDataDetail(GeoData data) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withOpacity(0.9),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _getGeometryIcon(),
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Survey Data Details',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(data.createdAt),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo Section
                      ...data.formData.entries.where((entry) => _isPhotoField(entry.key) && !_isOssField(entry.key)).map((entry) {
                        // Handle PhotoMetadata format
                        List<String> photoPaths = [];
                        
                        if (entry.value is List) {
                          final list = entry.value as List;
                          
                          for (var item in list) {
                            // Handle PhotoMetadata format
                            if (item is Map) {
                              final localPath = item['localPath'];
                              if (localPath != null && localPath.toString().isNotEmpty) {
                                final pathStr = localPath.toString();
                                final file = File(pathStr);
                                if (file.existsSync()) {
                                  photoPaths.add(pathStr);
                                }
                              }
                            }
                            // Handle old string format (backward compatibility)
                            else if (item is String && item.isNotEmpty) {
                              final file = File(item);
                              if (file.existsSync()) {
                                photoPaths.add(item);
                              }
                            }
                          }
                        } else if (entry.value is String && entry.value.toString().isNotEmpty) {
                          final path = entry.value.toString();
                          final file = File(path);
                          if (file.existsSync()) {
                            photoPaths = [path];
                          }
                        }
                        
                        if (photoPaths.isNotEmpty) {
                          
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.photo_camera,
                                      size: 20,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.key,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        Text(
                                          '${photoPaths.length} photo${photoPaths.length > 1 ? "s" : ""}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Display photos in a grid if multiple
                              if (photoPaths.length > 1)
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 8,
                                    childAspectRatio: 1.2,
                                  ),
                                  itemCount: photoPaths.length,
                                  itemBuilder: (context, index) {
                                    final photoPath = photoPaths[index];
                                    final photoFile = File(photoPath);
                                    final fileExists = photoFile.existsSync();
                                    
                                    return GestureDetector(
                                      onTap: () {
                                        if (fileExists) {
                                          _showFullImage(photoPath);
                                        }
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(12),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.1),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: fileExists
                                              ? Image.file(
                                                  photoFile,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return _buildImageErrorWidget();
                                                  },
                                                )
                                              : _buildImageNotFoundWidget(photoPath),
                                        ),
                                      ),
                                    );
                                  },
                                )
                              else
                                // Single photo display
                                GestureDetector(
                                  onTap: () {
                                    final photoFile = File(photoPaths[0]);
                                    if (photoFile.existsSync()) {
                                      _showFullImage(photoPaths[0]);
                                    }
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: () {
                                        final photoFile = File(photoPaths[0]);
                                        final fileExists = photoFile.existsSync();
                                        
                                        if (fileExists) {
                                          return Image.file(
                                            photoFile,
                                            width: double.infinity,
                                            height: 250,
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) {
                                              return _buildImageErrorWidget();
                                            },
                                          );
                                        } else {
                                          return _buildImageNotFoundWidget(photoPaths[0]);
                                        }
                                      }(),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 24),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      }),
                      
                      // Form Data Section
                      if (data.formData.entries.any((entry) => !_isPhotoField(entry.key) && !_isOssField(entry.key))) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 20,
                              color: Theme.of(context).primaryColor,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Form Data',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...data.formData.entries.where((entry) => !_isPhotoField(entry.key) && !_isOssField(entry.key)).map((entry) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    entry.key,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    recordValueText(
                                        entry.key, entry.value, _currentProject),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                      ],
                      
                      // Location Points Section
                      Row(
                        children: [
                          Icon(
                            Icons.my_location,
                            size: 20,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Location Points',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Theme.of(context).primaryColor.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              color: Theme.of(context).primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${data.points.length} point${data.points.length > 1 ? "s" : ""} recorded',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isPhotoField(String fieldName) {
    // Cek berdasarkan field type di project
    final field = _currentProject.formFields.where((f) => f.label == fieldName).firstOrNull;
    if (field != null) {
      return field.type == FieldType.photo;
    }
    
    // Fallback: cek berdasarkan nama field
    final lowerName = fieldName.toLowerCase();
    return lowerName.contains('photo') || 
           lowerName.contains('image') || 
           lowerName.contains('picture') ||
           lowerName.contains('foto') ||
           lowerName.contains('gambar');
  }

  bool _isOssField(String fieldName) {
    // Exclude fields yang berakhiran _oss_urls, _oss_keys, atau mengandung 'oss'
    final lowerName = fieldName.toLowerCase();
    return lowerName.endsWith('_oss_urls') || 
           lowerName.endsWith('_oss_keys') ||
           lowerName.endsWith('_oss_url') ||
           lowerName.endsWith('_oss_key') ||
           lowerName.contains('_oss_') ||
           lowerName.startsWith('oss_');
  }

  Widget _buildImageErrorWidget() {
    return Container(
      height: 250,
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.broken_image_rounded,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load image',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'The image file may be corrupted',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageNotFoundWidget(String path) {
    return Container(
      height: 250,
      color: Colors.orange[50],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_not_supported_rounded,
                size: 64,
                color: Colors.orange[400],
              ),
              const SizedBox(height: 12),
              Text(
                'Image file not found',
                style: TextStyle(
                  color: Colors.orange[800],
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                path,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getGeometryIcon() {
    switch (_currentProject.geometryType) {
      case GeometryType.point:
        return Icons.location_on;
      case GeometryType.line:
        return Icons.timeline;
      case GeometryType.polygon:
        return Icons.pentagon_outlined;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _showFullImage(String imagePath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Photo'),
            backgroundColor: Colors.black,
          ),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.file(File(imagePath)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _exportProjectTemplate() async {
    try {
      final templateService = ProjectTemplateService();
      final templateData = templateService.exportAsTemplate(_currentProject);
      final jsonString = const JsonEncoder.withIndent('  ').convert(templateData);

      // Show export dialog
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.file_download, color: Theme.of(context).primaryColor),
                const SizedBox(width: 6),
                const Text('Export Template'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Template: ${_currentProject.name}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Geometry: ${_currentProject.geometryType.toString().split('.').last.toUpperCase()}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  'Fields: ${_currentProject.formFields.length}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      jsonString,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        await templateService.copyTemplateToClipboard(templateData);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('Template copied to clipboard'),
                                ],
                              ),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      await _downloadTemplate(templateData);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(loggedErrorMessage('Could not export the template', e, tag: 'EXPORT'))),
              ],
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadTemplate(Map<String, dynamic> templateData) async {
    try {
      // Generate default filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final projectName = _currentProject.name.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
      final defaultFileName = '${projectName}_template_$timestamp.json';

      // Convert template to JSON string
      final jsonString = const JsonEncoder.withIndent('  ').convert(templateData);
      final bytes = Uint8List.fromList(utf8.encode(jsonString));

      String? outputPath;
      
      // Platform-specific handling
      if (Platform.isAndroid || Platform.isIOS) {
        // For Android/iOS, use bytes parameter which handles saving automatically
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Template As',
          fileName: defaultFileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: bytes, // This will save the file automatically on mobile
        );
      } else {
        // For desktop platforms, get path and write manually
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Template As',
          fileName: defaultFileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        
        if (outputPath != null && outputPath.isNotEmpty) {
          // Ensure .json extension
          if (!outputPath.toLowerCase().endsWith('.json')) {
            outputPath += '.json';
          }
          
          // Write template to selected file
          final file = File(outputPath);
          await file.writeAsString(jsonString);
        }
      }

      if (outputPath == null) {
        // User cancelled
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Template saved successfully!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Saved to: $outputPath',
                  style: const TextStyle(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(loggedErrorMessage('Could not save the file', e, tag: 'EXPORT'))),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }
}

typedef _ExportJob = ({Project project, List<GeoData> records});

/// Entry point isolate ekspor GeoJSON → (json, jumlah fitur, id dilewati).
(String, int, List<String>) _encodeGeoJsonExport(_ExportJob job) {
  final export = GeoExport.geoJson(job.project, job.records);
  return (export.encode(), export.featureCount, export.skippedIds);
}

/// Entry point isolate ekspor CSV.
String _encodeCsvExport(_ExportJob job) =>
    GeoExport.csv(job.project, job.records);
