/// Baris Project/PT untuk satu Jenis Analisis.
///
/// Endpoint: `GET /api/palmanalisis/types/{type_code}/companies/` (paginated).
/// Satu baris = satu project (unik per Jenis x PT).
class AnalysisCompany {
  final int companyId;
  final String compName;
  final String compCode;
  final String compGroup;
  final int fileCount;
  final DateTime? lastUpdated;

  AnalysisCompany({
    required this.companyId,
    required this.compName,
    required this.compCode,
    required this.compGroup,
    required this.fileCount,
    required this.lastUpdated,
  });

  factory AnalysisCompany.fromJson(Map<String, dynamic> json) {
    return AnalysisCompany(
      companyId: json['company_id'] as int,
      compName: json['comp_name'] as String? ?? '',
      compCode: json['comp_code'] as String? ?? '',
      compGroup: json['comp_group'] as String? ?? '',
      fileCount: (json['file_count'] as num?)?.toInt() ?? 0,
      lastUpdated: json['last_updated'] != null
          ? DateTime.tryParse(json['last_updated'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'company_id': companyId,
        'comp_name': compName,
        'comp_code': compCode,
        'comp_group': compGroup,
        'file_count': fileCount,
        'last_updated': lastUpdated?.toIso8601String(),
      };
}
