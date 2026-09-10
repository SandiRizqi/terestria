import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/analysis/analysis_company_model.dart';
import '../../services/analysis_report_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/analysis/analysis_company_tile.dart';
import 'analysis_files_screen.dart';

/// Daftar Project (PT) untuk satu Jenis Analisis.
///
/// `GET /api/palmanalisis/types/{type_code}/companies/` — paginated + search
/// server-side.
class AnalysisCompaniesScreen extends StatefulWidget {
  final String typeCode;
  final String typeName;
  final AnalysisReportService? service;

  const AnalysisCompaniesScreen({
    Key? key,
    required this.typeCode,
    required this.typeName,
    this.service,
  }) : super(key: key);

  @override
  State<AnalysisCompaniesScreen> createState() =>
      _AnalysisCompaniesScreenState();
}

class _AnalysisCompaniesScreenState extends State<AnalysisCompaniesScreen> {
  late final AnalysisReportService _service =
      widget.service ?? AnalysisReportService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  final List<AnalysisCompany> _companies = [];
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
      final res = await _service.fetchCompanies(
        widget.typeCode,
        page: 1,
        search: _search.isEmpty ? null : _search,
      );
      if (!mounted) return;
      setState(() {
        _companies
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
      final res = await _service.fetchCompanies(
        widget.typeCode,
        page: _page + 1,
        search: _search.isEmpty ? null : _search,
      );
      if (!mounted) return;
      setState(() {
        _companies.addAll(res.data);
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

  void _openCompany(AnalysisCompany company) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalysisFilesScreen(
          typeCode: widget.typeCode,
          companyId: company.companyId,
          title: company.compName,
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
        title: Text(
          widget.typeName,
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
          hintText: 'Cari PT (nama / kode)...',
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
    if (_companies.isEmpty) {
      return const _EmptyView();
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
      itemCount: _companies.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _companies.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final company = _companies[index];
        return AnalysisCompanyTile(
          company: company,
          onTap: () => _openCompany(company),
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
        Icon(Icons.business_outlined, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Belum ada PT untuk jenis ini',
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
