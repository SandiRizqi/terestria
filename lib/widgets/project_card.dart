import 'package:flutter/material.dart';
import 'package:geoform_app/theme/app_theme.dart';
import '../models/project_model.dart';
import '../services/auth_service.dart';
import '../services/tracking/tracking_session_manager.dart';
import '../utils/project_list.dart';
import '../utils/project_permissions.dart';
import 'project/manage_collectors_dialog.dart';

class ProjectCard extends StatefulWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  /// Dipanggil saat collectors berhasil diupdate, agar parent bisa reload
  final ValueChanged<Project>? onProjectUpdated;

  /// Ringkasan record project di HP (jumlah, belum ter-upload, gagal).
  final ProjectDataStats stats;

  /// User yang login; null → dibaca sendiri dari AuthService.
  final String? currentUsername;

  /// Untuk test; bawaan jam sekarang.
  final DateTime? now;

  const ProjectCard({
    Key? key,
    required this.project,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
    this.onProjectUpdated,
    this.stats = ProjectDataStats.empty,
    this.currentUsername,
    this.now,
  }) : super(key: key);

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard>
    with SingleTickerProviderStateMixin {
  String? _currentUsername;

  late final AnimationController _blinkController;
  late final Animation<double> _blink;
  final TrackingSessionManager _tracking = TrackingSessionManager.instance;

  bool get _hasSession => _tracking.isActive(widget.project.id);

  /// Sedang merekam (sesi ada & tidak di-pause) → badge REC berkedip.
  bool get _isTracking =>
      _tracking.sessionFor(widget.project.id)?.isRecording ?? false;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _blink = Tween<double>(begin: 0.35, end: 1.0).animate(_blinkController);
    _tracking.addListener(_onTrackingChanged);
    _syncBlink();
    _loadUsername();
  }

  void _onTrackingChanged() {
    if (!mounted) return;
    setState(_syncBlink);
  }

  /// Jalankan animasi kelap-kelip hanya saat project ini sedang tracking.
  void _syncBlink() {
    if (_isTracking) {
      if (!_blinkController.isAnimating) {
        _blinkController.repeat(reverse: true);
      }
    } else {
      if (_blinkController.isAnimating) {
        _blinkController.stop();
      }
    }
  }

  @override
  void dispose() {
    _tracking.removeListener(_onTrackingChanged);
    _blinkController.dispose();
    super.dispose();
  }

  /// Badge statis untuk sesi yang tidak merekam: JEDA (paused) atau
  /// BELUM DISIMPAN (sudah Stop, draft menunggu disimpan).
  Widget _buildIdleSessionBadge() {
    final pending =
        _tracking.sessionFor(widget.project.id)?.pendingSave ?? false;
    final color = pending ? const Color(0xFF1D4ED8) : const Color(0xFFB45309);
    return Container(
      key: ValueKey(pending
          ? 'tracking-pending-${widget.project.id}'
          : 'tracking-paused-${widget.project.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(pending ? Icons.save_outlined : Icons.pause_rounded,
              size: 11, color: color),
          const SizedBox(width: 2),
          Text(
            pending ? 'NOT SAVED' : 'PAUSED',
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Badge "REC" berkedip saat project sedang aktif merekam.
  Widget _buildTrackingBadge() {
    return FadeTransition(
      key: ValueKey('tracking-active-${widget.project.id}'),
      opacity: _blink,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.fiber_manual_record, size: 10, color: Color(0xFFEF4444)),
            SizedBox(width: 3),
            Text(
              'REC',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? get _username => widget.currentUsername ?? _currentUsername;

  Future<void> _loadUsername() async {
    if (widget.currentUsername != null) return;
    final authService = AuthService();
    final user = await authService.getUser();
    if (mounted) {
      setState(() {
        _currentUsername = user?.username;
      });
    }
  }

  /// Hanya pembuat yang boleh mengedit project (server mengabaikan perubahan
  /// dari user lain). Project lama tanpa pembuat tidak bisa diedit di app.
  bool _canEditProject() =>
      isProjectCreator(widget.project, _username);

  /// Hanya created_by yang boleh manage collectors
  bool _canManageCollectors() =>
      isProjectCreator(widget.project, _username);

  Future<void> _openManageCollectors() async {
    final username = _username;
    if (username == null) return;

    final updatedProject = await showDialog<Project>(
      context: context,
      builder: (_) => ManageCollectorsDialog(
        project: widget.project,
        currentUsername: username,
      ),
    );

    if (updatedProject != null && widget.onProjectUpdated != null) {
      widget.onProjectUpdated!(updatedProject);
    }
  }

  bool _canDeleteProject() {
    return true;
  }

  void _handleEdit() {
    if (_canEditProject()) {
      widget.onEdit();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.lock, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('You don\'t have permission to edit this project'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _handleDelete() {
    if (_canDeleteProject()) {
      widget.onDelete();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.lock, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('You don\'t have permission to delete this project'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final (geometryIcon, geometryColor, geometryLabel) =
        _geometryStyle(widget.project.geometryType);
    final (syncLabel, syncTone) = projectSyncTag(widget.project, widget.stats);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: geometryColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(geometryIcon, color: geometryColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.project.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            projectSubtitle(widget.project, widget.stats,
                                widget.now ?? DateTime.now()),
                            style: const TextStyle(
                                fontSize: 13, color: AppTheme.textSecondary),
                          ),
                          if (widget.project.description.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.project.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ],
                      ),
                    ),
                    _actionsMenu(),
                  ],
                ),
                const SizedBox(height: 10),
                // Wrap agar tag + badge tracking tak overflow di layar sempit.
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _tag(geometryLabel, TagTone.neutral),
                    _tag(syncLabel, syncTone),
                    if (isFromServer(widget.project, _username))
                      _tag('From server', TagTone.neutral),
                    if (_isTracking)
                      _buildTrackingBadge()
                    else if (_hasSession)
                      _buildIdleSessionBadge(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Menu aksi kartu: collectors, edit (hanya pembuat), hapus.
  Widget _actionsMenu() {
    final canEdit = _canEditProject();
    return PopupMenuButton<String>(
      tooltip: 'Project actions',
      icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
      onSelected: (value) {
        switch (value) {
          case 'collectors':
            _openManageCollectors();
          case 'edit':
            _handleEdit();
          case 'delete':
            _handleDelete();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'collectors',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading:
                const Icon(Icons.group_outlined, color: AppTheme.primaryGreen),
            title: Text(_canManageCollectors()
                ? 'Manage collectors'
                : 'View collectors'),
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              canEdit ? Icons.edit_rounded : Icons.lock_outline_rounded,
              color: canEdit ? AppTheme.primaryColor : AppTheme.textSecondary,
            ),
            title: const Text('Edit project'),
            subtitle: canEdit ? null : const Text('Only the creator can edit'),
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline_rounded,
                color: AppTheme.errorColor),
            title: Text('Delete project',
                style: TextStyle(color: AppTheme.errorColor)),
          ),
        ),
      ],
    );
  }

  static (IconData, Color, String) _geometryStyle(GeometryType type) {
    switch (type) {
      case GeometryType.point:
        return (Icons.place_outlined, AppTheme.pointColor, 'Point');
      case GeometryType.line:
        return (Icons.timeline, AppTheme.lineColor, 'Line');
      case GeometryType.polygon:
        return (Icons.pentagon_outlined, AppTheme.polygonColor, 'Polygon');
    }
  }

  /// Tag status kecil (template): netral abu-abu, sukses hijau, peringatan
  /// kuning, bahaya merah — warna dari AppTheme.
  Widget _tag(String label, TagTone tone) {
    final (bg, fg) = switch (tone) {
      TagTone.neutral => (Colors.grey.shade100, AppTheme.textPrimary),
      TagTone.success => (
          AppTheme.successColor.withValues(alpha: 0.14),
          AppTheme.darkGreen,
        ),
      TagTone.warning => (
          AppTheme.warningColor.withValues(alpha: 0.20),
          const Color(0xFFB45309),
        ),
      TagTone.danger => (
          AppTheme.errorColor.withValues(alpha: 0.12),
          AppTheme.errorColor,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
