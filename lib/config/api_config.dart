class ApiConfig {
  // Base URL backend
  static const String baseUrl = 'https://jango-dev1.tap-agri.com';

  static const String authUrl = 'https://jango-dev1.tap-agri.com/loginldap/';

  static const String bundleName = 'com.sandi.geoformApp';

  
  // Endpoints
  static const String syncDataEndpoint = '/mobile/geodata/';
  static const String syncProjectEndpoint = '/mobile/projects/';
  
  // Timeout settings
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
  
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
