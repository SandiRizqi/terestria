import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/project_model.dart';
import '../../services/collector_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';

/// Dialog untuk melihat dan mengelola collectors suatu project.
/// - Hanya created_by yang boleh add/remove collector.
/// - Penambahan hanya dari hasil search API (tidak bisa input manual).
class ManageCollectorsDialog extends StatefulWidget {
  final Project project;
  final String currentUsername;

  const ManageCollectorsDialog({
    Key? key,
    required this.project,
    required this.currentUsername,
  }) : super(key: key);

  @override
  State<ManageCollectorsDialog> createState() => _ManageCollectorsDialogState();
}

class _ManageCollectorsDialogState extends State<ManageCollectorsDialog> {
  final CollectorService _collectorService = CollectorService();
  final StorageService _storageService = StorageService();
  final TextEditingController _searchController = TextEditingController();

  // Working copy yang bisa dimodifikasi
  late List<String> _currentCollectors;

  // Hasil search API
  List<UserSearchResult> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  // State simpan
  bool _isSaving = false;

  // Debounce timer
  Timer? _debounceTimer;

  bool get _canManage =>
      widget.currentUsername.trim().toLowerCase() ==
      (widget.project.createdBy ?? '').trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    // Buat working copy dari collectors saat ini
    _currentCollectors = List<String>.from(widget.project.collectors);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    // Reset hasil kalau kosong
    if (query.isEmpty) {
      _debounceTimer?.cancel();
      setState(() {
        _searchResults = [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }

    // Debounce 500ms
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _doSearch(query);
    });
  }

  Future<void> _doSearch(String query) async {
    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await _collectorService.searchUsers(query);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchError = 'Error searching users: $e';
          _isSearching = false;
        });
      }
    }
  }

  void _addCollector(String username) {
    if (_currentCollectors.any(
      (c) => c.trim().toLowerCase() == username.trim().toLowerCase(),
    )) {
      // Sudah ada
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$username is already a collector'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _currentCollectors.add(username);
    });
  }

  void _removeCollector(String username) {
    setState(() {
      _currentCollectors.removeWhere(
        (c) => c.trim().toLowerCase() == username.trim().toLowerCase(),
      );
    });
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    final result = await _collectorService.updateCollectors(
      widget.project.id,
      _currentCollectors,
    );

    if (!mounted) return;

    if (result.success) {
      // Update local storage
      final updatedProject = widget.project.copyWith(
        collectors: _currentCollectors,
        updatedAt: DateTime.now(),
      );
      await _storageService.saveProject(updatedProject);

      setState(() => _isSaving = false);
      Navigator.of(context).pop(updatedProject); // Return updated project
    } else {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text(result.message ?? 'Failed to update collectors')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildCurrentCollectorsSection(),
                    if (_canManage) ...[
                      const SizedBox(height: 20),
                      _buildSearchSection(),
                    ],
                  ],
                ),
              ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.group, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Manage Collectors',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.project.name,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Badge permission
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _canManage
                  ? Colors.white.withOpacity(0.25)
                  : Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _canManage ? Icons.edit : Icons.visibility,
                  color: Colors.white,
                  size: 11,
                ),
                const SizedBox(width: 4),
                Text(
                  _canManage ? 'Owner' : 'View Only',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentCollectorsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.people_outline, size: 15, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Current Collectors (${_currentCollectors.length})',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_currentCollectors.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                Icon(Icons.person_off_outlined, size: 32, color: Colors.grey[400]),
                const SizedBox(height: 6),
                Text(
                  'No collectors yet',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ],
            ),
          )
        else
          ...(_currentCollectors.map((username) => _buildCollectorTile(username))),
      ],
    );
  }

  Widget _buildCollectorTile(String username) {
    final isCreator = username.trim().toLowerCase() ==
        (widget.project.createdBy ?? '').trim().toLowerCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isCreator
            ? const Color(0xFF6366F1).withOpacity(0.06)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCreator
              ? const Color(0xFF6366F1).withOpacity(0.2)
              : Colors.grey[200]!,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: isCreator
              ? const Color(0xFF6366F1).withOpacity(0.15)
              : Colors.grey[200],
          child: Text(
            username.isNotEmpty ? username[0].toUpperCase() : '?',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isCreator ? const Color(0xFF6366F1) : Colors.grey[600],
            ),
          ),
        ),
        title: Text(
          username,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        subtitle: isCreator
            ? const Text(
                'Project Owner',
                style: TextStyle(fontSize: 10, color: Color(0xFF6366F1)),
              )
            : null,
        trailing: (_canManage && !isCreator)
            ? IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 18),
                color: Colors.red[400],
                tooltip: 'Remove collector',
                onPressed: () => _removeCollector(username),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            : null,
      ),
    );
  }

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.person_add_outlined, size: 15, color: AppTheme.textSecondary),
            SizedBox(width: 6),
            Text(
              'Add Collector',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Search field
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search username...',
            hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
            prefixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : const Icon(Icons.search, size: 18),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () => _searchController.clear(),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
          ),
          style: const TextStyle(fontSize: 13),
        ),

        // Info hint
        if (_searchController.text.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Type to search users. Only users from search results can be added.',
              style: TextStyle(fontSize: 10, color: Colors.grey[400], fontStyle: FontStyle.italic),
            ),
          ),

        // Error
        if (_searchError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _searchError!,
              style: const TextStyle(fontSize: 11, color: Colors.red),
            ),
          ),

        // Search results
        if (_searchResults.isNotEmpty && _searchController.text.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[200]!),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: _searchResults.map((user) {
                final alreadyAdded = _currentCollectors.any(
                  (c) => c.trim().toLowerCase() == user.username.trim().toLowerCase(),
                );

                return InkWell(
                  onTap: alreadyAdded ? null : () => _addCollector(user.username),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: alreadyAdded
                              ? Colors.grey[200]
                              : AppTheme.primaryColor.withOpacity(0.12),
                          child: Text(
                            user.username.isNotEmpty
                                ? user.username[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: alreadyAdded
                                  ? Colors.grey[400]
                                  : AppTheme.primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            user.username,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: alreadyAdded ? Colors.grey[400] : Colors.black87,
                            ),
                          ),
                        ),
                        if (alreadyAdded)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Added',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.add,
                                  size: 11,
                                  color: AppTheme.primaryColor,
                                ),
                                SizedBox(width: 2),
                                Text(
                                  'Add',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],

        // No results
        if (_searchResults.isEmpty &&
            !_isSearching &&
            _searchController.text.isNotEmpty &&
            _searchError == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Text(
                'No users found for "${_searchController.text}"',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter() {
    // Cek apakah ada perubahan
    final original = List<String>.from(widget.project.collectors)..sort();
    final current = List<String>.from(_currentCollectors)..sort();
    final hasChanges = original.join(',') != current.join(',');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(top: BorderSide(color: Colors.grey[200]!)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Keterangan perubahan
          if (_canManage && hasChanges)
            Text(
              'Unsaved changes',
              style: TextStyle(
                fontSize: 11,
                color: Colors.orange[700],
                fontWeight: FontWeight.w500,
              ),
            )
          else
            const SizedBox.shrink(),

          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _canManage ? 'Cancel' : 'Close',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (_canManage) ...[
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: (!hasChanges || _isSaving) ? null : _saveChanges,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined, size: 15),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Save Changes',
                    style: const TextStyle(fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    disabledBackgroundColor: Colors.grey[300],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
