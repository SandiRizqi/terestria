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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: geometryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      geometryIcon,
                      color: geometryColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.project.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 4),
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
                    decoration: BoxDecoration(
                      color: canEdit 
                          ? AppTheme.primaryColor.withOpacity(0.08)
                          : Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      icon: Icon(
                        canEdit ? Icons.edit_outlined : Icons.lock_outline,
                        size: 20,
                      ),
                      color: canEdit 
                          ? AppTheme.primaryColor 
                          : Colors.grey[400],
                      onPressed: _handleEdit,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      tooltip: canEdit ? 'Edit Project' : 'No permission to edit',
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Delete button
                  Container(
                    decoration: BoxDecoration(
                      color: canEdit 
                          ? Colors.red.withOpacity(0.08)
                          : Colors.grey.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: IconButton(
                      icon: Icon(
                        canDelete ? Icons.delete_outline : Icons.lock_outline,
                        size: 20,
                      ),
                      color: canDelete
                          ? Colors.red[700] 
                          : Colors.grey[400],
                      onPressed: _handleDelete,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                      tooltip: canDelete ? 'Delete Project' : 'No permission to delete',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.project.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
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
          const Icon(Icons.person_outline, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            creator,
            style: const TextStyle(
              fontSize: 12,
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
