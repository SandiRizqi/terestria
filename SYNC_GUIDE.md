# Panduan Sync Data ke Backend

## Cara Menggunakan Fitur Sync

### 1. **Konfigurasi Backend**

Sebelum menggunakan fitur sync, Anda perlu konfigurasi URL backend di file:
`lib/config/api_config.dart`

```dart
class ApiConfig {
  // Ganti dengan URL backend Anda
  static const String baseUrl = 'https://your-backend-url.com/api';
}
```

**Contoh URL:**
- Production: `https://api.example.com/api`
- Development: `http://192.168.1.100:3000/api`
- Localhost: `http://10.0.2.2:3000/api` (untuk Android Emulator)

### 2. **Indikator Online/Offline**

Di layar Project Detail, Anda akan melihat indikator status koneksi di AppBar:
- 🟢 **Online** - Terhubung ke internet, bisa sync
- 🔴 **Offline** - Tidak ada koneksi, sync disabled

Aplikasi otomatis memonitor status koneksi setiap 5 detik.

### 3. **Sync Data**

#### Cara Sync:
1. Buka Project yang memiliki data belum ter-sync
2. Anda akan melihat notifikasi "X records not synced" di bagian bawah stats card
3. Pastikan status **Online** 🟢
4. Klik tombol **"Sync Now"**
5. Konfirmasi sync
6. Tunggu hingga proses selesai

#### Status Sync:
- ✅ **Success** - Semua data berhasil di-sync
- ⚠️ **Partial** - Sebagian data berhasil, sebagian gagal
- ❌ **Failed** - Semua data gagal di-sync

### 4. **Tracking Status Sync**

Setiap record memiliki status sync:
- **Not Synced** - Data belum di-upload ke server (icon ☁️ dengan warna orange)
- **Synced** - Data sudah berhasil di-upload (icon ✓ dengan warna hijau)

Status ini ditampilkan di:
- Stats card (jumlah unsynced records)
- List item geo data
- Detail geo data

### 5. **Error Handling**

Jika sync gagal, aplikasi akan menampilkan:
- Dialog error dengan daftar pesan error
- Data yang gagal **TIDAK** akan di-mark sebagai synced
- Anda bisa retry sync kapan saja

**Kemungkinan Error:**
- "No internet connection" - Periksa koneksi internet
- "Connection timeout" - Server terlalu lama merespon
- "Server error: 500" - Ada masalah di backend
- "Invalid response format" - Response dari server tidak sesuai

### 6. **Best Practices**

#### Kapan Sync Data:
- Setelah mengumpulkan beberapa data di lapangan
- Saat terhubung ke WiFi (hemat kuota)
- Di akhir hari kerja
- Sebelum backup/export data

#### Tips:
- ✅ Pastikan koneksi internet stabil
- ✅ Sync secara berkala (jangan terlalu banyak data sekaligus)
- ✅ Check status sync sebelum hapus data lokal
- ⚠️ Jangan tutup aplikasi saat proses sync
- ⚠️ Hindari sync saat sinyal lemah

### 7. **Troubleshooting**

#### Tombol Sync Disabled?
- Periksa indikator status - harus **Online** 🟢
- Pastikan ada data yang belum di-sync
- Restart aplikasi jika masih disabled

#### Sync Selalu Failed?
1. Test URL backend dengan Postman/curl
2. Periksa format response dari backend (lihat BACKEND_CONFIG.md)
3. Check log backend untuk error
4. Pastikan API key (jika ada) sudah benar

#### Sync Lama Sekali?
- Periksa kecepatan internet
- Kurangi jumlah data yang di-sync sekaligus
- Sesuaikan timeout di `api_config.dart`:
  ```dart
  static const Duration connectionTimeout = Duration(seconds: 60);
  ```

#### Data Sudah Sync tapi Tidak Ada di Backend?
- Periksa log backend
- Pastikan backend menyimpan data ke database
- Check struktur tabel database
- Validasi response dari backend (harus return success: true)

### 8. **Manual Retry Sync**

Jika sync gagal:
1. Data akan tetap berstatus "Not Synced"
2. Perbaiki masalah koneksi/backend
3. Klik "Sync Now" lagi untuk retry
4. Hanya data yang belum synced yang akan di-upload ulang

### 9. **Sync vs Export**

**Sync:**
- Kirim data ke backend server
- Real-time via API
- Butuh koneksi internet
- Otomatis mark sebagai synced

**Export:**
- Download data dalam format JSON
- Bisa dilakukan offline
- Untuk backup atau migrasi
- Tidak mengubah status sync

## Keamanan

- Data dikirim via HTTPS (production)
- Gunakan API key untuk autentikasi
- Backend harus validasi semua input
- Encrypt data sensitif di formData

## Support

Jika mengalami masalah sync:
1. Check dokumentasi BACKEND_CONFIG.md
2. Test koneksi dengan `curl` atau Postman
3. Periksa log backend untuk error detail
4. Hubungi tim development

---

**Catatan:** Fitur sync bersifat optional. Anda tetap bisa menggunakan aplikasi secara offline dan export data manual jika backend belum tersedia.
