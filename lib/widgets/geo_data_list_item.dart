import 'package:flutter/material.dart';
import 'package:geoform_app/theme/app_theme.dart';
import 'dart:io';
import '../models/geo_data_model.dart';
import '../models/project_model.dart';
import '../models/form_field_model.dart';

class GeoDataListItem extends StatelessWidget {
  final GeoData geoData;
  final GeometryType geometryType;
  final VoidCallback? onDelete; // Nullable - null jika tidak bisa delete
  final VoidCallback? onEdit; // Nullable - null jika tidak bisa edit
  final VoidCallback onTap;
  final Project? project;

  const GeoDataListItem({
    Key? key,
    required this.geoData,
    required this.geometryType,
    this.onDelete, // Optional
    this.onEdit, // Optional
    required this.onTap,
    this.project,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Debug log untuk melihat status button
    //print('📋 Rendering GeoDataListItem:');
    //print('   ID: ${geoData.id}');
    //print('   CollectedBy: ${geoData.collectedBy}');
    //print('   onEdit: ${onEdit != null ? "enabled" : "disabled"}');
    //print('   onDelete: ${onDelete != null ? "enabled" : "disabled"}');
    
    IconData icon;
    Color color;

    switch (geometryType) {
      case GeometryType.point:
        icon = Icons.location_on;
        color = const Color(0xFFEF4444);
        break;
      case GeometryType.line:
        icon = Icons.timeline;
        color = const Color(0xFF3B82F6);
        break;
      case GeometryType.polygon:
        icon = Icons.pentagon_outlined;
        color =  AppTheme.primaryColor;
        break;
    }

    final photoPath = _getPhotoPath();
    final hasPhoto = photoPath != null && photoPath.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo Header (if available)
            if (hasPhoto)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.file(
                    File(photoPath),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[200],
                        child: Icon(
                          Icons.broken_image,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                      );
                    },
                  ),
                ),
              ),
            
            // Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: color, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getTitle(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: Colors.grey[500],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _formatDate(geoData.createdAt),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Edit button
                      Container(
                        decoration: BoxDecoration(
                          color: onEdit != null 
                              ? AppTheme.primaryColor.withOpacity(0.08)
                              : Colors.grey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: Icon(
                            onEdit != null ? Icons.edit_outlined : Icons.lock_outline,
                            size: 20,
                          ),
                          color: onEdit != null 
                              ? AppTheme.primaryColor 
                              : Colors.grey[400],
                          onPressed: onEdit,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                          tooltip: onEdit != null ? 'Edit' : 'No permission to edit',
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Delete button
                      Container(
                        decoration: BoxDecoration(
                          color: onDelete != null 
                              ? Colors.red.withOpacity(0.08)
                              : Colors.grey.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: IconButton(
                          icon: Icon(
                            onDelete != null ? Icons.delete_outline : Icons.lock_outline,
                            size: 20,
                          ),
                          color: onDelete != null 
                              ? Colors.red[700] 
                              : Colors.grey[400],
                          onPressed: onDelete,
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                          tooltip: onDelete != null ? 'Delete' : 'No permission to delete',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildInfoChip(
                        Icons.my_location,
                        '${geoData.points.length} point${geoData.points.length > 1 ? "s" : ""}',
                        color,
                      ),
                      if (geoData.formData.isNotEmpty)
                        _buildInfoChip(
                          Icons.description_outlined,
                          '${geoData.formData.length} field${geoData.formData.length > 1 ? "s" : ""}',
                          const Color(0xFF10B981),
                        ),
                      if (hasPhoto)
                        _buildInfoChip(
                          Icons.photo_camera,
                          'Photo',
                          const Color(0xFF8B5CF6),
                        ),
                      _buildSyncStatusChip(),
                      if (geoData.collectedBy != null)
                        _buildCollectorChip(),
                    ],
                  ),
                  if (geoData.formData.isNotEmpty && !hasPhoto) ...[
                    const SizedBox(height: 14),
                    Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.grey[200]!,
                            Colors.grey[100]!,
                            Colors.grey[200]!,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...geoData.formData.entries.where((entry) => !_isPhotoField(entry.key)).take(2).map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  color: Colors.grey[700],
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 3,
                              child: Text(
                                _formatFormValue(entry.value),
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF1F2937),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    if (_getNonPhotoFieldsCount() > 2)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+ ${_getNonPhotoFieldsCount() - 2} more field${_getNonPhotoFieldsCount() - 2 > 1 ? "s" : ""}',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatusChip() {
    final isSynced = geoData.isSynced;
    final color = isSynced ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final icon = isSynced ? Icons.cloud_done : Icons.cloud_upload;
    final label = isSynced ? 'Synced' : 'Local';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectorChip() {
    const color = Color(0xFF6366F1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person_outline, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            geoData.collectedBy!,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _getTitle() {
    // Try to get first non-photo form field value as title
    if (geoData.formData.isNotEmpty) {
      final firstNonPhotoEntry = geoData.formData.entries.firstWhere(
        (entry) => !_isPhotoField(entry.key),
        orElse: () => geoData.formData.entries.first,
      );
      final firstValue = firstNonPhotoEntry.value.toString();
      if (firstValue.isNotEmpty && !firstValue.startsWith('/')) {
        return firstValue.length > 40 
            ? '${firstValue.substring(0, 40)}...' 
            : firstValue;
      }
    }
    return 'Survey Data #${geoData.id.substring(0, 8)}';
  }

  String? _getPhotoPath() {
    // Look for photo fields in formData
    for (var entry in geoData.formData.entries) {
      if (_isPhotoField(entry.key) && entry.value != null) {
        // Handle List (new PhotoMetadata format or old string format)
        if (entry.value is List) {
          final photos = (entry.value as List).where((p) => p != null).toList();
          if (photos.isNotEmpty) {
            final firstPhoto = photos[0];
            
            // Handle PhotoMetadata format (Map)
            if (firstPhoto is Map) {
              final localPath = firstPhoto['localPath'];
              if (localPath != null && localPath.toString().isNotEmpty) {
                final pathStr = localPath.toString();
                if (File(pathStr).existsSync()) {
                  return pathStr;
                }
              }
            }
            // Handle old string format
            else if (firstPhoto is String && firstPhoto.isNotEmpty) {
              if (File(firstPhoto).existsSync()) {
                return firstPhoto;
              }
            }
          }
        }
        // Handle single string (old format)
        else if (entry.value is String) {
          final value = entry.value.toString();
          if (value.isNotEmpty && File(value).existsSync()) {
            return value;
          }
        }
      }
    }
    return null;
  }

  bool _isPhotoField(String fieldName) {
    // Jika project tersedia, cek berdasarkan field type
    if (project != null) {
      final field = project!.formFields.where((f) => f.label == fieldName).firstOrNull;
      if (field != null) {
        return field.type == FieldType.photo;
      }
    }
    
    // Fallback: cek berdasarkan nama field
    final lowerName = fieldName.toLowerCase();
    return lowerName.contains('photo') || 
           lowerName.contains('image') || 
           lowerName.contains('picture') ||
           lowerName.contains('foto') ||
           lowerName.contains('gambar');
  }

  int _getNonPhotoFieldsCount() {
    return geoData.formData.entries
        .where((entry) => !_isPhotoField(entry.key))
        .length;
  }

  String _formatFormValue(dynamic value) {
    if (value == null) return '';

    // Jika sudah DateTime langsung format
    if (value is DateTime) {
      return _formatDate(value);
    }

    // Jika string tapi bisa di-parse jadi DateTime
    if (value is String) {
      try {
        final parsed = DateTime.parse(value);
        return _formatDate(parsed);
      } catch (_) {
        // bukan tanggal valid → tampilkan apa adanya
        return value;
      }
    }

    // Default: tampilkan apa adanya
    return value.toString();
  }


  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
