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
  
  // PDF Georeferencing
  final double? pdfMinLat;
  final double? pdfMinLon;
  final double? pdfMaxLat;
  final double? pdfMaxLon;
  final double? pdfCenterLat;
  final double? pdfCenterLon;
  
  // PDF Overlay Mode (faster than tiles!)
  final String? pdfOverlayImagePath;  // Path to overlay.png
  final bool useOverlayMode;  // true = use overlay, false = use tiles

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
    this.pdfMinLat,
    this.pdfMinLon,
    this.pdfMaxLat,
    this.pdfMaxLon,
    this.pdfCenterLat,
    this.pdfCenterLon,
    this.pdfOverlayImagePath,
    this.useOverlayMode = true,  // Default to overlay mode
  });

  bool get isPdfBasemap => type == BasemapType.pdf;
  bool get isPdfProcessing => pdfStatus == PdfProcessingStatus.processing;
  bool get isPdfReady => pdfStatus == PdfProcessingStatus.completed;
  bool get isPdfFailed => pdfStatus == PdfProcessingStatus.failed;
  bool get hasPdfGeoreferencing => pdfMinLat != null && pdfMinLon != null && pdfMaxLat != null && pdfMaxLon != null;
  
  /// Get PDF bounds as List [south, west, north, east]
  List<double>? get pdfBounds {
    if (!hasPdfGeoreferencing) return null;
    return [pdfMinLat!, pdfMinLon!, pdfMaxLat!, pdfMaxLon!];
  }

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
    double? pdfMinLat,
    double? pdfMinLon,
    double? pdfMaxLat,
    double? pdfMaxLon,
    double? pdfCenterLat,
    double? pdfCenterLon,
    String? pdfOverlayImagePath,
    bool? useOverlayMode,
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
      pdfMinLat: pdfMinLat ?? this.pdfMinLat,
      pdfMinLon: pdfMinLon ?? this.pdfMinLon,
      pdfMaxLat: pdfMaxLat ?? this.pdfMaxLat,
      pdfMaxLon: pdfMaxLon ?? this.pdfMaxLon,
      pdfCenterLat: pdfCenterLat ?? this.pdfCenterLat,
      pdfCenterLon: pdfCenterLon ?? this.pdfCenterLon,
      pdfOverlayImagePath: pdfOverlayImagePath ?? this.pdfOverlayImagePath,
      useOverlayMode: useOverlayMode ?? this.useOverlayMode,
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
      'pdfMinLat': pdfMinLat,
      'pdfMinLon': pdfMinLon,
      'pdfMaxLat': pdfMaxLat,
      'pdfMaxLon': pdfMaxLon,
      'pdfCenterLat': pdfCenterLat,
      'pdfCenterLon': pdfCenterLon,
      'pdfOverlayImagePath': pdfOverlayImagePath,
      'useOverlayMode': useOverlayMode,
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
      pdfMinLat: json['pdfMinLat']?.toDouble(),
      pdfMinLon: json['pdfMinLon']?.toDouble(),
      pdfMaxLat: json['pdfMaxLat']?.toDouble(),
      pdfMaxLon: json['pdfMaxLon']?.toDouble(),
      pdfCenterLat: json['pdfCenterLat']?.toDouble(),
      pdfCenterLon: json['pdfCenterLon']?.toDouble(),
      pdfOverlayImagePath: json['pdfOverlayImagePath'],
      useOverlayMode: json['useOverlayMode'] ?? true,
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
