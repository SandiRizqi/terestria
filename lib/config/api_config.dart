class ApiConfig {
  // Base URL backend
  static const String baseUrl = 'https://django.tap-agri.com';

  static const String authUrl = '${baseUrl}/loginldap/';

  static const String bundleName = 'io.github.sandirizqi.terestria';

  static const String appVersion = '4.4.0';
  // Endpoints
  static const String syncDataEndpoint = '/mobile/geodata/';
  static const String syncProjectEndpoint = '/mobile/projects/';
  static const String userSearchEndpoint = '/mobile/users/search/';

  // PalmAnalisis (Analysis Report) endpoints — same host as baseUrl
  static const String analysisTypesEndpoint = '/api/palmanalisis/types/';
  static String analysisCompaniesEndpoint(String typeCode) =>
      '/api/palmanalisis/types/$typeCode/companies/';
  static String analysisFilesEndpoint(String typeCode, int companyId) =>
      '/api/palmanalisis/types/$typeCode/companies/$companyId/files/';
  static String analysisFileDetailEndpoint(int fileId) =>
      '/api/palmanalisis/files/$fileId/';

  // Road data (navigation) endpoints
  static const String roadsCompaniesEndpoint = '/mobile/roads/companies/';
  static const String roadsOsmEndpoint = '/mobile/roads/osm/';
  
  // FCM Token Endpoints
  static const String fcmTokenRegisterEndpoint = '/mobile/fcm-tokens/register/';
  static const String fcmTokenListEndpoint = '/mobile/fcm-tokens/';
  static const String fcmTokenDeactivateByDeviceEndpoint = '/mobile/fcm-tokens/deactivate_by_device/';
  static const String fcmTokenDeactivateAllEndpoint = '/mobile/fcm-tokens/deactivate_all/';
  
  // Timeout settings
  static const Duration connectionTimeout = Duration(seconds: 300);
  static const Duration receiveTimeout = Duration(seconds: 600);

  /// Timeout khusus upload file (foto). Lebih longgar dari request biasa karena
  /// foto bisa besar dan jaringan lapangan lambat, tapi tetap dibatasi supaya
  /// upload tidak menggantung tanpa batas.
  static const Duration uploadTimeout = Duration(seconds: 120);
  
  // API Keys (jika diperlukan)
  static const String? apiKey = null; // Ganti dengan API key Anda
  
  // Headers default
  static Map<String, String> get defaultHeaders => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (apiKey != null) 'Authorization': 'Token $apiKey',
  };
  
  // Full URL helper
  static String getFullUrl(String endpoint) {
    return '$baseUrl$endpoint';
  }
}
