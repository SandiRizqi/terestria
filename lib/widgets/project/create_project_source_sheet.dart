import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Sumber project baru (template "Create project · choose source").
enum CreateProjectSource { scratch, template, server }

/// Bottom sheet "Create Project": mulai dari nol, impor template, atau ambil
/// dari server. Null bila dibatalkan.
Future<CreateProjectSource?> showCreateProjectSourceSheet(BuildContext context) {
  return showModalBottomSheet<CreateProjectSource>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.cardBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Create Project',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'How would you like to create your project?',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 18),
            const _SourceOption(
              source: CreateProjectSource.scratch,
              icon: Icons.add_rounded,
              title: 'Start from scratch',
              description: 'Name, geometry type and your own form fields',
              primary: true,
            ),
            const SizedBox(height: 12),
            const _SourceOption(
              source: CreateProjectSource.template,
              icon: Icons.upload_file_rounded,
              title: 'Import template',
              description: 'Load a .json template shared by your team',
            ),
            const SizedBox(height: 12),
            const _SourceOption(
              source: CreateProjectSource.server,
              icon: Icons.cloud_download_outlined,
              title: 'From server',
              description: 'Download a project assigned to you',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: AppTheme.inputBackground,
                  foregroundColor: AppTheme.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Cancel',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SourceOption extends StatelessWidget {
  final CreateProjectSource source;
  final IconData icon;
  final String title;
  final String description;

  /// Pilihan utama: garis tepi & kotak ikon hijau penuh.
  final bool primary;

  const _SourceOption({
    required this.source,
    required this.icon,
    required this.title,
    required this.description,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: primary ? AppTheme.primaryGreen : Colors.grey.shade200,
          width: primary ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pop(context, source),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: primary
                      ? AppTheme.primaryGreen
                      : AppTheme.primaryGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon,
                    color: primary ? Colors.white : AppTheme.primaryGreen),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                          fontSize: 13.5, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
