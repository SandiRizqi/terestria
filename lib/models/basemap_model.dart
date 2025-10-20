enum BasemapType { builtin, custom, pdf }

enum PdfProcessingStatus {
  pending,
  processing,
  completed,
  failed,
}

class Basemap {
  final String id;
  final String name;
  final BasemapType type;
  final String urlTemplate;
  final int minZoom;
  final int maxZoom;
  final String? attribution;
  final bool isDefault;
  
  // PDF-specific fields
  final String? pdfPath;
  final PdfProcessingStatus? pdfStatus;
  final double? processingProgress;
  final String? processingMessage;
  final DateTime? createdAt;

  Basemap({
    required this.id,
    required this.name,
    required this.type,
    required this.urlTemplate,
    this.minZoom = 0,
    this.maxZoom = 18,
    this.attribution,
    this.isDefault = false,
    this.pdfPath,
    this.pdfStatus,
    this.processingProgress,
    this.processingMessage,
    this.createdAt,
  });

  bool get isPdfBasemap => type == BasemapType.pdf;
  bool get isPdfProcessing => pdfStatus == PdfProcessingStatus.processing;
  bool get isPdfReady => pdfStatus == PdfProcessingStatus.completed;
  bool get isPdfFailed => pdfStatus == PdfProcessingStatus.failed;

  Basemap copyWith({
    String? id,
    String? name,
    BasemapType? type,
    String? urlTemplate,
    int? minZoom,
    int? maxZoom,
    String? attribution,
    bool? isDefault,
    String? pdfPath,
    PdfProcessingStatus? pdfStatus,
    double? processingProgress,
    String? processingMessage,
    DateTime? createdAt,
  }) {
    return Basemap(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      urlTemplate: urlTemplate ?? this.urlTemplate,
      minZoom: minZoom ?? this.minZoom,
      maxZoom: maxZoom ?? this.maxZoom,
      attribution: attribution ?? this.attribution,
      isDefault: isDefault ?? this.isDefault,
      pdfPath: pdfPath ?? this.pdfPath,
      pdfStatus: pdfStatus ?? this.pdfStatus,
      processingProgress: processingProgress ?? this.processingProgress,
      processingMessage: processingMessage ?? this.processingMessage,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.toString().split('.').last,
      'urlTemplate': urlTemplate,
      'minZoom': minZoom,
      'maxZoom': maxZoom,
      'attribution': attribution,
      'isDefault': isDefault,
      'pdfPath': pdfPath,
      'pdfStatus': pdfStatus?.toString().split('.').last,
      'processingProgress': processingProgress,
      'processingMessage': processingMessage,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory Basemap.fromJson(Map<String, dynamic> json) {
    return Basemap(
      id: json['id'],
      name: json['name'],
      type: BasemapType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
      ),
      urlTemplate: json['urlTemplate'],
      minZoom: json['minZoom'] ?? 0,
      maxZoom: json['maxZoom'] ?? 18,
      attribution: json['attribution'],
      isDefault: json['isDefault'] ?? false,
      pdfPath: json['pdfPath'],
      pdfStatus: json['pdfStatus'] != null
          ? PdfProcessingStatus.values.firstWhere(
              (e) => e.toString().split('.').last == json['pdfStatus'],
            )
          : null,
      processingProgress: json['processingProgress']?.toDouble(),
      processingMessage: json['processingMessage'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
    );
  }

  // Default basemaps
  static List<Basemap> getDefaultBasemaps() {
    return [
      Basemap(
        id: 'osm_road',
        name: 'OpenStreetMap (Road)',
        type: BasemapType.builtin,
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        maxZoom: 19,
        attribution: '© OpenStreetMap contributors',
        isDefault: true,
      ),
      Basemap(
        id: 'satellite',
        name: 'Satellite',
        type: BasemapType.builtin,
        urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
        maxZoom: 19,
        attribution: '© Esri',
      ),
      Basemap(
        id: 'topo',
        name: 'Topographic',
        type: BasemapType.builtin,
        urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
        maxZoom: 17,
        attribution: '© OpenTopoMap',
      ),
    ];
  }
}
