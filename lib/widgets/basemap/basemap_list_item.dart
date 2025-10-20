import 'package:flutter/material.dart';
import '../../models/basemap_model.dart';
import '../../theme/app_theme.dart';

class BasemapListItem extends StatelessWidget {
  final Basemap basemap;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const BasemapListItem({
    Key? key,
    required this.basemap,
    required this.isSelected,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isBuiltin = basemap.type == BasemapType.builtin;
    final isPdf = basemap.type == BasemapType.pdf;

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingMedium),
      child: InkWell(
        onTap: basemap.isPdfReady || !isPdf ? onTap : null,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          child: Row(
            children: [
              _buildIcon(),
              const SizedBox(width: AppTheme.spacingMedium),
              Expanded(child: _buildContent()),
              if (!isBuiltin) _buildActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    IconData icon;
    Color color;
    Color bgColor;

    if (isSelected) {
      icon = Icons.map;
      color = Colors.white;
      bgColor = AppTheme.primaryGreen;
    } else if (basemap.isPdfProcessing) {
      icon = Icons.hourglass_empty;
      color = Colors.orange;
      bgColor = Colors.orange.withOpacity(0.2);
    } else if (basemap.isPdfFailed) {
      icon = Icons.error_outline;
      color = AppTheme.errorColor;
      bgColor = AppTheme.errorColor.withOpacity(0.2);
    } else {
      icon = basemap.isPdfBasemap ? Icons.picture_as_pdf : Icons.map;
      color = AppTheme.primaryGreen;
      bgColor = AppTheme.lightGreen.withOpacity(0.2);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTitle(),
        const SizedBox(height: 4),
        _buildBadges(),
        if (basemap.isPdfProcessing) ...[
          const SizedBox(height: 8),
          _buildProgressBar(),
        ],
        if (!basemap.type.toString().contains('builtin')) ...[
          const SizedBox(height: 4),
          _buildSubtitle(),
        ],
      ],
    );
  }

  Widget _buildTitle() {
    return Row(
      children: [
        Flexible(
          child: Text(
            basemap.name,
            style: TextStyle(
              fontSize: 16,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        if (isSelected) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Active',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBadges() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _buildBadge(
          label: _getTypeLabel(),
          color: _getTypeColor(),
        ),
        if (!basemap.isPdfProcessing && !basemap.isPdfFailed)
          _buildBadge(
            label: 'Zoom: ${basemap.minZoom}-${basemap.maxZoom}',
            color: AppTheme.textSecondary,
          ),
      ],
    );
  }

  String _getTypeLabel() {
    if (basemap.type == BasemapType.builtin) return 'Built-in';
    if (basemap.isPdfProcessing) return 'Processing...';
    if (basemap.isPdfFailed) return 'Failed';
    if (basemap.isPdfBasemap) return 'PDF Map';
    return 'Custom';
  }

  Color _getTypeColor() {
    if (basemap.type == BasemapType.builtin) return Colors.blue;
    if (basemap.isPdfProcessing) return Colors.orange;
    if (basemap.isPdfFailed) return AppTheme.errorColor;
    return AppTheme.darkGreen;
  }

  Widget _buildBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = basemap.processingProgress ?? 0.0;
    final message = basemap.processingMessage ?? 'Processing...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: progress > 0 ? progress : null,
          backgroundColor: Colors.grey[200],
          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
        ),
        const SizedBox(height: 4),
        Text(
          message,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.textSecondary,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildSubtitle() {
    if (basemap.isPdfFailed) {
      return Text(
        basemap.processingMessage ?? 'Processing failed',
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.errorColor,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }

    if (!basemap.isPdfProcessing && basemap.urlTemplate.isNotEmpty) {
      return Text(
        basemap.urlTemplate,
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.textSecondary,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildActions(BuildContext context) {
    if (basemap.isPdfProcessing) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (isSelected) {
      return const Icon(Icons.check_circle, color: AppTheme.primaryGreen);
    }

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value == 'edit' && onEdit != null) onEdit!();
        if (value == 'delete' && onDelete != null) onDelete!();
      },
      itemBuilder: (context) => [
        if (!basemap.isPdfBasemap)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit, size: 20),
                SizedBox(width: 12),
                Text('Edit'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, size: 20, color: AppTheme.errorColor),
              SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: AppTheme.errorColor)),
            ],
          ),
        ),
      ],
    );
  }
}
