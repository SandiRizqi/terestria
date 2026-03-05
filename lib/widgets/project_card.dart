import 'package:flutter/material.dart';
import 'package:geoform_app/theme/app_theme.dart';
import '../models/project_model.dart';
import '../services/auth_service.dart';

class ProjectCard extends StatefulWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const ProjectCard({
    Key? key,
    required this.project,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
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

  bool _canEditProject() {
    //print(widget.project.createdBy);
    if (_currentUsername == null) return false;
    if (widget.project.createdBy == null) return true; // Old data without creator
    
    // Normalize untuk perbandingan
    final normalizedProjectCreator = widget.project.createdBy!.trim().toLowerCase();
    final normalizedCurrentUser = _currentUsername!.trim().toLowerCase();
    
    return normalizedProjectCreator == normalizedCurrentUser;
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
                        Text(
                          widget.project.geometryType.toString().split('.').last.toUpperCase(),
                          style: TextStyle(
                            color: geometryColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      color: canEdit 
                          ? AppTheme.primaryColor 
                          : Colors.grey[400],
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
                        canDelete ? Icons.delete_outline_rounded : Icons.lock_outline_rounded,
                        size: 16,
                      ),
                      color: canDelete
                          ? Colors.red[600] 
                          : Colors.grey[400],
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
            ],
          ),
        ),
      ),
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
