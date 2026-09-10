import 'package:flutter/material.dart';
import '../../models/analysis/analysis_file_model.dart';
import '../../theme/app_theme.dart';

/// Baris satu File dalam sebuah project analisis, dengan aksi "Add as Basemap"
/// untuk file PDF georeference.
class AnalysisFileTile extends StatelessWidget {
  final AnalysisFile file;

  /// Dipanggil saat user menekan "Add as Basemap". Null → aksi dinonaktifkan.
  final VoidCallback? onAddAsBasemap;

  /// Dipanggil saat user menekan "Share" (bagikan PDF ke WA/app lain).
  /// Null → aksi dinonaktifkan.
  final VoidCallback? onShare;

  const AnalysisFileTile({
    Key? key,
    required this.file,
    this.onAddAsBasemap,
    this.onShare,
  }) : super(key: key);

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final created = _formatDate(file.createdAt);
    final subtitleParts = <String>[
      file.fileSizeLabel,
      if (created.isNotEmpty) created,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.errorColor.withOpacity(0.1),
                    borderRadius:
                        BorderRadius.circular(AppTheme.borderRadiusSmall),
                  ),
                  child: const Icon(Icons.picture_as_pdf_rounded,
                      color: AppTheme.errorColor),
                ),
                const SizedBox(width: AppTheme.spacingMedium),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (file.blockCode.isNotEmpty) ...[
                            _BlockChip(code: file.blockCode),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              subtitleParts.join(' • '),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (file.isPdf) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onAddAsBasemap,
                      icon: const Icon(Icons.add_location_alt_outlined,
                          size: 18),
                      label: const Text('Add as Basemap'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: const Text('Share'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BlockChip extends StatelessWidget {
  final String code;

  const _BlockChip({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        code,
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.darkGreen,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
