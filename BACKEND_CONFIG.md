# Backend Configuration Guide

## Konfigurasi API Backend

File konfigurasi backend terletak di: `lib/config/api_config.dart`

### Mengubah URL Backend

Edit file `lib/config/api_config.dart`:

```dart
class ApiConfig {
  // Ganti dengan URL backend Anda
  static const String baseUrl = 'https://your-backend-url.com/api';
  
  // Endpoints - sesuaikan dengan struktur API Anda
  static const String syncDataEndpoint = '/sync/geodata';
  static const String syncProjectEndpoint = '/sync/project';
}
```

### Menambahkan API Key (Opsional)

Jika backend Anda memerlukan autentikasi:

```dart
class ApiConfig {
  // ...
  static const String? apiKey = 'your-api-key-here';
  // ...
}
```

## Format Data yang Dikirim ke Backend

Ketika melakukan sync, aplikasi akan mengirim data dalam format JSON berikut:

### Endpoint: POST /sync/geodata

**Request Body:**
```json
{
  "id": "uuid-geodata",
  "project_id": "uuid-project",
  "project_name": "Nama Project",
  "geometry_type": "point|line|polygon",
  "form_data": {
    "field1": "value1",
    "field2": "value2",
    "photo": "/path/to/photo.jpg"
  },
  "points": [
    {
      "latitude": -6.2088,
      "longitude": 106.8456
    }
  ],
  "created_at": "2024-01-01T12:00:00.000Z",
  "synced_at": "2024-01-01T12:05:00.000Z"
}
```

**Expected Response (Success):**
```json
{
  "success": true,
  "message": "Data synced successfully",
  "data": {
    "id": "server-generated-id",
    "synced_at": "2024-01-01T12:05:00.000Z"
  }
}
```

**Expected Response (Error):**
```json
{
  "success": false,
  "message": "Error message here",
  "error": "Detailed error information"
}
```

## Contoh Implementasi Backend (Node.js/Express)

```javascript
const express = require('express');
const router = express.Router();

// POST /api/sync/geodata
router.post('/sync/geodata', async (req, res) => {
  try {
    const geoData = req.body;
    
    // Validasi data
    if (!geoData.id || !geoData.project_id) {
      return res.status(400).json({
        success: false,
        message: 'Missing required fields'
      });
    }
    
    // Simpan ke database
    // await db.geodata.insert(geoData);
    
    res.status(200).json({
      success: true,
      message: 'Data synced successfully',
      data: {
        id: geoData.id,
        synced_at: new Date().toISOString()
      }
    });
    
  } catch (error) {
    console.error('Sync error:', error);
    res.status(500).json({
      success: false,
      message: 'Internal server error',
      error: error.message
    });
  }
});

module.exports = router;
```

## Contoh Implementasi Backend (Laravel/PHP)

```php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Models\GeoData;

class SyncController extends Controller
{
    public function syncGeoData(Request $request)
    {
        try {
            // Validasi
            $validated = $request->validate([
                'id' => 'required|string',
                'project_id' => 'required|string',
                'project_name' => 'required|string',
                'geometry_type' => 'required|string',
                'form_data' => 'required|array',
                'points' => 'required|array',
                'created_at' => 'required|date',
            ]);
            
            // Simpan ke database
            $geoData = GeoData::updateOrCreate(
                ['id' => $validated['id']],
                $validated
            );
            
            return response()->json([
                'success' => true,
                'message' => 'Data synced successfully',
                'data' => [
                    'id' => $geoData->id,
                    'synced_at' => now()->toIso8601String(),
                ],
            ], 200);
            
        } catch (\Exception $e) {
            return response()->json([
                'success' => false,
                'message' => 'Sync failed',
                'error' => $e->getMessage(),
            ], 500);
        }
    }
}
```

## Testing Backend Connection

Untuk test koneksi ke backend, gunakan curl atau Postman:

```bash
curl -X POST https://your-backend-url.com/api/sync/geodata \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d '{
    "id": "test-123",
    "project_id": "project-456",
    "project_name": "Test Project",
    "geometry_type": "point",
    "form_data": {"test": "data"},
    "points": [{"latitude": -6.2088, "longitude": 106.8456}],
    "created_at": "2024-01-01T12:00:00.000Z",
    "synced_at": "2024-01-01T12:05:00.000Z"
  }'
```

## Troubleshooting

### Aplikasi tidak bisa connect ke backend

1. **Periksa URL Backend**
   - Pastikan URL di `api_config.dart` sudah benar
   - Pastikan backend sudah running
   - Test dengan curl atau Postman

2. **CORS Error (Web)**
   - Backend harus mengizinkan CORS dari domain aplikasi
   - Tambahkan header CORS di backend:
     ```
     Access-Control-Allow-Origin: *
     Access-Control-Allow-Methods: GET, POST, PUT, DELETE
     Access-Control-Allow-Headers: Content-Type, Authorization
     ```

3. **SSL/HTTPS Error**
   - Pastikan backend menggunakan HTTPS jika deploy ke production
   - Untuk development, bisa menggunakan HTTP (ganti di api_config.dart)

4. **Timeout Error**
   - Sesuaikan `connectionTimeout` dan `receiveTimeout` di api_config.dart
   - Periksa kecepatan internet/server

5. **Authentication Error**
   - Periksa API key sudah benar
   - Pastikan header Authorization sudah sesuai format backend

### Data tidak tersimpan di backend

1. Periksa log backend untuk error
2. Validasi format data yang dikirim
3. Periksa database connection di backend
4. Test endpoint dengan data minimal dulu

## Status Codes

Aplikasi akan menganggap sync berhasil jika mendapat response:
- `200 OK` - Request berhasil
- `201 Created` - Data berhasil dibuat

Response code lain akan dianggap error dan data tidak akan di-mark sebagai synced.

## Security Recommendations

1. **Gunakan HTTPS** di production
2. **Implement API Key/Token** untuk autentikasi
3. **Validasi data** di sisi backend
4. **Rate limiting** untuk mencegah abuse
5. **Logging** untuk audit trail
6. **Encrypt sensitive data** di form_data jika diperlukan

## Contact

Jika ada pertanyaan atau butuh bantuan konfigurasi backend, silakan hubungi tim development.
