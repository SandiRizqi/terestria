import 'package:flutter/material.dart';
import '../../models/analysis/analysis_type_model.dart';
import '../../services/analysis_report_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/analysis/analysis_type_card.dart';
import 'analysis_companies_screen.dart';

/// Layar entry Analysis Report: daftar Jenis Analisis.
///
/// `GET /api/palmanalisis/types/`. Tap sebuah jenis membuka daftar PT.
class AnalysisTypesScreen extends StatefulWidget {
  /// Bisa di-inject untuk testing; default memakai instance produksi.
  final AnalysisReportService? service;

  const AnalysisTypesScreen({Key? key, this.service}) : super(key: key);

  @override
  State<AnalysisTypesScreen> createState() => _AnalysisTypesScreenState();
}

class _AnalysisTypesScreenState extends State<AnalysisTypesScreen> {
  late final AnalysisReportService _service =
      widget.service ?? AnalysisReportService();

  bool _isLoading = true;
  String? _errorMessage;
  List<AnalysisType> _types = [];

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// Daftar yang ditampilkan setelah difilter query (client-side, karena
  /// `fetchAnalysisTypes` mengembalikan seluruh daftar tanpa paginasi).
  List<AnalysisType> get _filteredTypes {
    if (_query.isEmpty) return _types;
    final q = _query.toLowerCase();
    return _types
        .where((t) =>
            t.name.toLowerCase().contains(q) ||
            t.description.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final types = await _service.fetchAnalysisTypes();
      if (!mounted) return;
      setState(() {
        _types = types;
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

  String _friendlyError(Object e) {
    if (e is AnalysisApiException) return e.message;
    return 'Gagal memuat jenis analisis. Periksa koneksi Anda.';
  }

  void _openType(AnalysisType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysisCompaniesScreen(
          typeCode: type.code,
          typeName: type.name,
          service: widget.service,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryGreen,
        title: const Text(
          'Analysis Report',
          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        elevation: 0,
      ),
      body: Column(
        children: [
          if (!_isLoading && _errorMessage == null && _types.isNotEmpty)
            _buildSearchBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
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
        onChanged: (value) => setState(() => _query = value.trim()),
        decoration: InputDecoration(
          hintText: 'Cari jenis analisis...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
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
      return _ErrorView(message: _errorMessage!, onRetry: _load);
    }
    if (_types.isEmpty) {
      return const _EmptyView();
    }
    final types = _filteredTypes;
    if (types.isEmpty) {
      return _NoResultView(query: _query);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      itemCount: types.length,
      itemBuilder: (context, index) {
        final type = types[index];
        return AnalysisTypeCard(type: type, onTap: () => _openType(type));
      },
    );
  }
}

/// Ditampilkan saat search tidak menemukan jenis analisis yang cocok.
class _NoResultView extends StatelessWidget {
  final String query;

  const _NoResultView({required this.query});

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView agar RefreshIndicator tetap berfungsi.
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Icon(Icons.search_off_rounded, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Center(
          child: Text(
            'Tidak ada hasil untuk "$query"',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView so RefreshIndicator still works on empty state.
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.3),
        Icon(Icons.analytics_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Belum ada jenis analisis',
            style: TextStyle(fontSize: 15, color: Colors.grey),
          ),
        ),
      ],
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
