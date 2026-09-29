import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../../models/analysis/analysis_file_model.dart';
import '../../models/basemap_model.dart';
import '../../services/analysis/analysis_basemap_name.dart';
import '../../services/analysis_report_service.dart';
import '../../services/analysis_pdf_downloader.dart';
import '../../services/basemap_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/pdf/pdf_basemap_importer.dart';
import '../../theme/app_theme.dart';
import '../../utils/share_origin.dart';
import '../../widgets/analysis/analysis_file_tile.dart';

/// Daftar File untuk satu Project (Jenis Analisis x PT).
///
/// `GET /api/palmanalisis/types/{type_code}/companies/{company_id}/files/` —
/// paginated + search server-side. Tiap file PDF punya aksi "Add as Basemap".
class AnalysisFilesScreen extends StatefulWidget {
  final String typeCode;
  final int companyId;
  final String title;

  /// Nama project (level pertama Analysis Report, `AnalysisType.name`) —
  /// jadi prefix nama basemap agar asal project-nya jelas.
  final String? projectName;
  final AnalysisReportService? service;

  const AnalysisFilesScreen({
    Key? key,
    required this.typeCode,
    required this.companyId,
    required this.title,
    this.projectName,
    this.service,
  }) : super(key: key);

  @override
  State<AnalysisFilesScreen> createState() => _AnalysisFilesScreenState();
}

class _AnalysisFilesScreenState extends State<AnalysisFilesScreen> {
  late final AnalysisReportService _service =
      widget.service ?? AnalysisReportService();
  late final AnalysisPdfDownloader _downloader =
      AnalysisPdfDownloader(reportService: _service);
  final BasemapService _basemapService = BasemapService();
  final PdfBasemapImporter _importer = PdfBasemapImporter();
  final Uuid _uuid = const Uuid();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  final List<AnalysisFile> _files = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _page = 1;
  bool _hasMore = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoadingMore || _isLoading) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _loadFirstPage(search: value.trim());
    });
  }

  Future<void> _loadFirstPage({String? search}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _search = search ?? _search;
    });
    try {
      final res = await _service.fetchFiles(
        widget.typeCode,
        widget.companyId,
        page: 1,
        search: _search.isEmpty ? null : _search,
      );
      if (!mounted) return;
      setState(() {
        _files
          ..clear()
          ..addAll(res.data);
        _page = 1;
        _hasMore = res.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _friendlyError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    try {
      final res = await _service.fetchFiles(
        widget.typeCode,
        widget.companyId,
        page: _page + 1,
        search: _search.isEmpty ? null : _search,
      );
      if (!mounted) return;
      setState(() {
        _files.addAll(res.data);
        _page += 1;
        _hasMore = res.hasMore;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
  }

  String _friendlyError(Object e) {
    if (e is AnalysisApiException) return e.message;
    return 'Gagal memuat data. Periksa koneksi Anda.';
  }

  /// Unduh PDF file → proses jadi overlay basemap → simpan. Butuh online.
  Future<void> _addAsBasemap(AnalysisFile file) async {
    // OSS download + refresh URL butuh koneksi.
    final online = await ConnectivityService().checkConnection();
    if (!mounted) return;
    if (!online) {
      _showSnack('Perlu koneksi internet untuk menambahkan basemap',
          isError: true);
      return;
    }

    final name = analysisBasemapName(widget.projectName, file.title);
    final status = ValueNotifier<String>('Mengunduh PDF...');
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddBasemapProgressDialog(title: name, status: status),
    );

    String? basemapId;
    try {
      final pdfPath = await _downloader.downloadPdf(file);

      basemapId = _uuid.v4();
      final base = Basemap(
        id: basemapId,
        name: name,
        type: BasemapType.pdf,
        urlTemplate: '',
        pdfPath: pdfPath,
        pdfStatus: PdfProcessingStatus.processing,
        processingProgress: 0.0,
        processingMessage: 'Memproses...',
        createdAt: DateTime.now(),
      );
      await _basemapService.saveBasemap(base);

      final completed = await _importer.process(
        base: base,
        pdfPath: pdfPath,
        onProgress: (progress, message) => status.value = message,
      );
      await _basemapService.saveBasemap(completed);

      if (!mounted) return;
      Navigator.pop(context); // tutup dialog progress
      _showSnack('Basemap "$name" berhasil ditambahkan');
    } on TimeoutException catch (e) {
      await _cleanupFailed(basemapId);
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack('Timeout: ${e.message}', isError: true);
    } catch (e) {
      await _cleanupFailed(basemapId);
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack(_addBasemapError(e), isError: true);
    } finally {
      status.dispose();
    }
  }

  /// Unduh PDF lalu buka share sheet sistem (WhatsApp, email, dsb.).
  /// Butuh online karena URL unduhan OSS di-refresh saat diunduh.
  Future<void> _sharePdf(AnalysisFile file) async {
    final online = await ConnectivityService().checkConnection();
    if (!mounted) return;
    if (!online) {
      _showSnack('Perlu koneksi internet untuk membagikan file',
          isError: true);
      return;
    }

    final status = ValueNotifier<String>('Menyiapkan file...');
    var dialogOpen = true;
    void closeDialog() {
      if (dialogOpen && mounted) {
        Navigator.pop(context);
        dialogOpen = false;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _AddBasemapProgressDialog(title: file.title, status: status),
    );

    try {
      final pdfPath = await _downloader.downloadPdf(file);
      if (!mounted) return;
      closeDialog(); // tutup progress sebelum share sheet muncul
      await Share.shareXFiles(
        [XFile(pdfPath, mimeType: 'application/pdf')],
        subject: file.title,
        // iOS/iPad butuh rect sumber untuk anchor share popover; tanpa ini
        // memicu PlatformException(sharePositionOrigin). Pakai bounds layar.
        sharePositionOrigin: shareOriginFor(context),
      );
    } on TimeoutException catch (e) {
      if (!mounted) return;
      closeDialog();
      _showSnack('Timeout: ${e.message}', isError: true);
    } catch (e) {
      if (!mounted) return;
      closeDialog();
      _showSnack(_shareError(e), isError: true);
    } finally {
      status.dispose();
    }
  }

  String _shareError(Object e) {
    if (e is AnalysisDownloadException) return e.message;
    if (e is AnalysisApiException) return e.message;
    return 'Gagal membagikan file: $e';
  }

  /// Hapus record processing bila proses gagal (agar tidak jadi sampah).
  Future<void> _cleanupFailed(String? basemapId) async {
    if (basemapId == null) return;
    try {
      await _basemapService.deleteBasemap(basemapId);
    } catch (_) {
      // Abaikan — record mungkin belum sempat dibuat.
    }
  }

  String _addBasemapError(Object e) {
    if (e is AnalysisDownloadException) return e.message;
    if (e is PdfBasemapImportException) return e.message;
    if (e is AnalysisApiException) return e.message;
    return 'Gagal menambahkan basemap: $e';
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.errorColor : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryGreen,
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadFirstPage(),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Cari file (judul / blok)...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _loadFirstPage(search: '');
                  },
                )
              : null,
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return _ErrorView(message: _errorMessage!, onRetry: () => _loadFirstPage());
    }
    if (_files.isEmpty) {
      return const _EmptyView();
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
      itemCount: _files.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _files.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final file = _files[index];
        return AnalysisFileTile(
          file: file,
          onAddAsBasemap: () => _addAsBasemap(file),
          onShare: () => _sharePdf(file),
        );
      },
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Belum ada file untuk PT ini',
            style: TextStyle(fontSize: 15, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

/// Dialog progress non-dismissible saat mengunduh & memproses PDF jadi basemap.
class _AddBasemapProgressDialog extends StatelessWidget {
  final String title;
  final ValueListenable<String> status;

  const _AddBasemapProgressDialog({required this.title, required this.status});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: status,
                  builder: (context, value, _) => Text(
                    value,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
        const SizedBox(height: 16),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Coba lagi'),
          ),
        ),
      ],
    );
  }
}
