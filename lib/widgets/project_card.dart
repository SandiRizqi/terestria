import 'package:flutter/material.dart';
import 'package:geoform_app/theme/app_theme.dart';
import '../models/project_model.dart';
import '../services/auth_service.dart';
import 'project/manage_collectors_dialog.dart';

class ProjectCard extends StatefulWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  /// Dipanggil saat collectors berhasil diupdate, agar parent bisa reload
  final ValueChanged<Project>? onProjectUpdated;

  const ProjectCard({
    Key? key,
    required this.project,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
    this.onProjectUpdated,
  }) : super(key: key);

  @override
  State<ProjectCard> createState() => _ProjectCardState();
}

class _ProjectCardState extends State<ProjectCard> {
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _loadUsername();
  }

  Future<void> _loadUsername() async {
    final authService = AuthService();
    final user = await authService.getUser();
    if (mounted) {
      setState(() {
        _currentUsername = user?.username;
      });
    }
  }

  /// Badge status sinkronisasi project ke server (Synced / Local).
  Widget _buildSyncBadge(bool isSynced) {
    final color = isSynced ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final icon = isSynced ? Icons.cloud_done : Icons.cloud_off;
    final label = isSynced ? 'Synced' : 'Local';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  bool _canEditProject() {
    //print(widget.project.createdBy);
    if (_currentUsername == null) return false;
    if (widget.project.createdBy == null) return true; // Old data without creator

    // Normalize untuk perbandingan
    final normalizedProjectCreator = widget.project.createdBy!.trim().toLowerCase();
    final normalizedCurrentUser = _currentUsername!.trim().toLowerCase();

    return normalizedProjectCreator == normalizedCurrentUser;
  }

  /// Hanya created_by yang boleh manage collectors
  bool _canManageCollectors() {
    if (_currentUsername == null) return false;
    if (widget.project.createdBy == null) return false;
    return widget.project.createdBy!.trim().toLowerCase() ==
        _currentUsername!.trim().toLowerCase();
  }

  Future<void> _openManageCollectors() async {
    if (_currentUsername == null) return;

    final updatedProject = await showDialog<Project>(
      context: context,
      builder: (_) => ManageCollectorsDialog(
        project: widget.project,
        currentUsername: _currentUsername!,
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
    IconData geometryIcon;
    Color geometryColor;

    switch (widget.project.geometryType) {
      case GeometryType.point:
        geometryIcon = Icons.place;
        geometryColor = AppTheme.pointColor;
        break;
      case GeometryType.line:
        geometryIcon = Icons.timeline;
        geometryColor = AppTheme.lineColor;
        break;
      case GeometryType.polygon:
        geometryIcon = Icons.crop_square;
        geometryColor = AppTheme.polygonColor;
        break;
    }

    final canEdit = _canEditProject();
    final canDelete = _canDeleteProject();
    final canManageCollectors = _canManageCollectors();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.getCardDecoration,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: geometryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: geometryColor.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        geometryIcon,
                        color: geometryColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.project.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                widget.project.geometryType.toString().split('.').last.toUpperCase(),
                                style: TextStyle(
                                  color: geometryColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildSyncBadge(widget.project.isSynced),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Manage Collectors button
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.group_outlined, size: 16),
                        color: Colors.teal[600],
                        onPressed: _openManageCollectors,
                        padding: EdgeInsets.zero,
                        tooltip: canManageCollectors
                            ? 'Manage Collectors'
                            : 'View Collectors',
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Edit button
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: canEdit
                            ? AppTheme.primaryColor.withOpacity(0.08)
                            : Colors.grey.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        icon: Icon(
                          canEdit ? Icons.edit_rounded : Icons.lock_outline_rounded,
                          size: 16,
                        ),
                        color: canEdit ? AppTheme.primaryColor : Colors.grey[400],
                        onPressed: _handleEdit,
                        padding: EdgeInsets.zero,
                        tooltip: canEdit ? 'Edit Project' : 'No permission to edit',
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Delete button
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: canDelete
                            ? Colors.red.withOpacity(0.08)
                            : Colors.grey.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: IconButton(
                        icon: Icon(
                          canDelete
                              ? Icons.delete_outline_rounded
                              : Icons.lock_outline_rounded,
                          size: 16,
                        ),
                        color: canDelete ? Colors.red[600] : Colors.grey[400],
                        onPressed: _handleDelete,
                        padding: EdgeInsets.zero,
                        tooltip: canDelete ? 'Delete Project' : 'No permission to delete',
                      ),
                    ),
                  ],
                ),
                if (widget.project.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.project.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildInfoChip(
                      Icons.edit_note,
                      '${widget.project.formFields.length} fields',
                    ),
                    _buildInfoChip(
                      Icons.calendar_today,
                      _formatDate(widget.project.createdAt),
                    ),
                    if (widget.project.createdBy != null)
                      _buildCreatorChip(widget.project.createdBy!),
                  ],
                ),
                // Collectors row
                if (widget.project.collectors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildCollectorsRow(widget.project.collectors),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollectorsRow(List<String> collectors) {
    const maxVisible = 3;
    final visible = collectors.take(maxVisible).toList();
    final overflow = collectors.length - maxVisible;

    return Row(
      children: [
        const Icon(Icons.group_outlined, size: 12, color: Colors.teal),
        const SizedBox(width: 5),
        ...visible.map((name) => _buildCollectorChip(name)),
        if (overflow > 0)
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '+$overflow more',
              style: TextStyle(
                fontSize: 9,
                color: Colors.teal[700],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCollectorChip(String username) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.withOpacity(0.2)),
      ),
      child: Text(
        username,
        style: TextStyle(
          fontSize: 9,
          color: Colors.teal[800],
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorChip(String creator) {
    const color = Color(0xFF6366F1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_outline, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            creator,
            style: const TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
