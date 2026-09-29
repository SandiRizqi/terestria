class ApiConfig {
  // Base URL backend
  static const String baseUrl = 'https://django.tap-agri.com';

  static const String authUrl = '${baseUrl}/loginldap/';

  static const String bundleName = 'io.github.sandirizqi.terestria';

  static const String appVersion = '4.4.2';
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
  /// Batas satu request JSON (koneksi + respons). Dulu 300 dtk → di sinyal
  /// lemah app tampak macet 5 menit sebelum gagal. 90 dtk masih cukup untuk
  /// satu halaman pull berisi track panjang di jaringan ±64 kbps.
  static const Duration requestTimeout = Duration(seconds: 90);

  /// Login: user menunggu di layar login → gagal cepat & beri pesan jelas.
  static const Duration loginTimeout = Duration(seconds: 30);

  /// Nama lama dipertahankan untuk kompatibilitas; kini = [requestTimeout].
  static const Duration connectionTimeout = requestTimeout;

  /// Timeout upload bawaan bila ukuran file tak diketahui.
  static const Duration uploadTimeout = Duration(seconds: 120);

  /// Timeout upload berdasar ukuran file: 30 dtk dasar + waktu kirim pada
  /// ±8 KB/s (≈64 kbps, sinyal lapangan buruk), dibatasi 60 dtk–10 menit.
  /// Foto 500 KB → ±90 dtk; foto PNG lama 5 MB → 10 menit (bukan gagal di 120 dtk).
  static Duration uploadTimeoutFor(int bytes) {
    final seconds = 30 + (bytes / (8 * 1024)).ceil();
    return Duration(seconds: seconds.clamp(60, 600));
  }
  
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
