import 'package:flutter/material.dart';
import '../../models/analysis/analysis_company_model.dart';
import '../../theme/app_theme.dart';

/// Baris satu Project/PT pada daftar sebuah Jenis Analisis.
class AnalysisCompanyTile extends StatelessWidget {
  final AnalysisCompany company;
  final VoidCallback? onTap;

  const AnalysisCompanyTile({Key? key, required this.company, this.onTap})
      : super(key: key);

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final updated = _formatDate(company.lastUpdated);
    return Card(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.borderRadiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.1),
                  borderRadius:
                      BorderRadius.circular(AppTheme.borderRadiusSmall),
                ),
                child:
                    const Icon(Icons.business_rounded, color: AppTheme.primaryBlue),
              ),
              const SizedBox(width: AppTheme.spacingMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.compName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      company.compGroup.isNotEmpty
                          ? '${company.compGroup} • ${company.fileCount} file${company.fileCount == 1 ? '' : 's'}'
                          : '${company.fileCount} file${company.fileCount == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    if (updated.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Updated $updated',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}
