/// Model untuk cloud basemap dari backend
class CloudBasemap {
  final int id;
  final String code;
  final String name;
  final String description;
  final CloudBasemapCompany company;
  final String tmsUrl;
  final String proxyUrl;
  final int minZoom;
  final int maxZoom;

  CloudBasemap({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.company,
    required this.tmsUrl,
    required this.proxyUrl,
    required this.minZoom,
    required this.maxZoom,
  });

  factory CloudBasemap.fromJson(Map<String, dynamic> json) {
    return CloudBasemap(
      id: json['id'] as int,
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      company: CloudBasemapCompany.fromJson(json['company'] as Map<String, dynamic>),
      tmsUrl: json['tmsUrl'] as String,
      proxyUrl: json['proxyUrl'] as String,
      minZoom: json['minZoom'] as int? ?? 0,
      maxZoom: json['maxZoom'] as int? ?? 20,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'description': description,
      'company': company.toJson(),
      'tmsUrl': tmsUrl,
      'proxyUrl': proxyUrl,
      'minZoom': minZoom,
      'maxZoom': maxZoom,
    };
  }
}

class CloudBasemapCompany {
  final int id;
  final String name;
  final String group;

  CloudBasemapCompany({
    required this.id,
    required this.name,
    required this.group,
  });

  factory CloudBasemapCompany.fromJson(Map<String, dynamic> json) {
    return CloudBasemapCompany(
      id: json['id'] as int,
      name: json['name'] as String,
      group: json['group'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'group': group,
    };
  }
}

/// Response model untuk API call
class CloudBasemapResponse {
  final bool success;
  final String message;
  final List<CloudBasemap> data;
  final int count;

  CloudBasemapResponse({
    required this.success,
    required this.message,
    required this.data,
    required this.count,
  });

  factory CloudBasemapResponse.fromJson(Map<String, dynamic> json) {
    return CloudBasemapResponse(
      success: json['success'] as bool,
      message: json['message'] as String,
      data: (json['data'] as List<dynamic>)
          .map((item) => CloudBasemap.fromJson(item as Map<String, dynamic>))
          .toList(),
      count: json['count'] as int,
    );
  }
}
