/// Jenis Analisis dari backend palmanalisis.
///
/// Endpoint: `GET /api/palmanalisis/types/` (non-paginated).
class AnalysisType {
  final int id;
  final String name;
  final String code;
  final String description;
  final String icon;

  /// Jumlah PT dalam scope yang punya >=1 file untuk jenis ini.
  final int companyCount;

  AnalysisType({
    required this.id,
    required this.name,
    required this.code,
    required this.description,
    required this.icon,
    required this.companyCount,
  });

  factory AnalysisType.fromJson(Map<String, dynamic> json) {
    return AnalysisType(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      code: json['code'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? '',
      companyCount: (json['company_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'code': code,
        'description': description,
        'icon': icon,
        'company_count': companyCount,
      };
}
