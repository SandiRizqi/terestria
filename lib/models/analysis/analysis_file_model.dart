/// File (FileRow) di dalam sebuah project analisis.
///
/// Endpoint: `GET /api/palmanalisis/types/{type_code}/companies/{id}/files/`
/// dan detail `GET /api/palmanalisis/files/{id}/`.
///
/// Catatan: [downloadUrl] bertanda tangan & kedaluwarsa +-1 jam. Ambil fresh
/// tepat sebelum mengunduh; jangan disimpan lama.
class AnalysisFile {
  final int id;
  final String title;
  final String blockCode;
  final String description;
  final String fileName;
  final int fileSize;
  final String contentType;
  final String downloadUrl;
  final String uploadedBy;
  final DateTime? createdAt;

  AnalysisFile({
    required this.id,
    required this.title,
    required this.blockCode,
    required this.description,
    required this.fileName,
    required this.fileSize,
    required this.contentType,
    required this.downloadUrl,
    required this.uploadedBy,
    required this.createdAt,
  });

  factory AnalysisFile.fromJson(Map<String, dynamic> json) {
    return AnalysisFile(
      id: json['id'] as int,
      title: json['title'] as String? ?? '',
      blockCode: json['block_code'] as String? ?? '',
      description: json['description'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      contentType: json['content_type'] as String? ?? '',
      downloadUrl: json['download_url'] as String? ?? '',
      uploadedBy: json['uploaded_by'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  /// True bila file adalah PDF (dari content-type atau ekstensi nama file).
  bool get isPdf =>
      contentType.toLowerCase().contains('pdf') ||
      fileName.toLowerCase().endsWith('.pdf');

  /// Ukuran file dalam satuan yang mudah dibaca (B / KB / MB / GB).
  String get fileSizeLabel {
    if (fileSize <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = fileSize.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final rounded = unit == 0 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
    return '$rounded ${units[unit]}';
  }

  /// Salinan dengan [downloadUrl] baru — dipakai saat me-refresh URL yang
  /// kedaluwarsa lewat endpoint file-detail.
  AnalysisFile copyWith({String? downloadUrl}) {
    return AnalysisFile(
      id: id,
      title: title,
      blockCode: blockCode,
      description: description,
      fileName: fileName,
      fileSize: fileSize,
      contentType: contentType,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      uploadedBy: uploadedBy,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'block_code': blockCode,
        'description': description,
        'file_name': fileName,
        'file_size': fileSize,
        'content_type': contentType,
        'download_url': downloadUrl,
        'uploaded_by': uploadedBy,
        'created_at': createdAt?.toIso8601String(),
      };
}
