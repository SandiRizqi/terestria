# Review Lapangan — Terestria v4.4.2 (+39)

Tanggal: 2026-09-29 · Cakupan: seluruh `lib/` (±58 rb baris) dengan fokus alur lapangan:
pengambilan titik/track → form & foto → penyimpanan lokal → sinkronisasi → peta offline.

Metode: review statis kode (Flutter SDK tidak tersedia di lingkungan review, jadi belum ada
uji di perangkat). Setiap temuan menyebut lokasi `file:baris` agar bisa diverifikasi.
Temuan diurutkan per prioritas:

| Prioritas | Arti |
|---|---|
| **P0** | Data hilang / rusak diam-diam. Perbaiki sebelum rilis berikutnya. |
| **P1** | Fitur gagal atau macet di kondisi lapangan umum (sinyal lemah, HP murah, RTK). |
| **P2** | Mutu/akurasi data menurun, atau hasil membingungkan. |
| **P3** | Kinerja, baterai, dan kepatuhan. |

---

## Ringkasan eksekutif

Lima risiko teratas:

1. **Titik tracking bisa hilang saat app dimatikan OS selagi surveyor terus bergerak.**
   Flush ke SQLite memakai debounce 2 dtk, padahal debounce itu di-reset setiap fix GPS
   (~1 dtk). Selama bergerak kontinu, flush praktis tidak pernah terjadi (A1).
2. **Sesi tracking dan draft dihapus otomatis saat app dibuka ulang** bila berumur >12 jam
   atau jumlahnya melebihi batas project. Tidak ada peringatan (A2).
3. **Sync bisa menimpa atau melewatkan data.** Pull menimpa edit lokal yang belum
   tersinkron. Watermark delta tetap maju walau record gagal disimpan, jadi record itu
   tidak pernah ditarik lagi (A3–A5).
4. **Mode RTK Emlid default (LLH) kemungkinan besar tidak menghasilkan titik sama sekali.**
   Parser membaca kolom tanggal sebagai lintang. Titik Emlid juga tidak pernah membawa
   nilai akurasi (A6).
5. **Tombol "Add Point" merekam titik tengah peta (crosshair), bukan posisi GPS**, dan
   metadata akurasi/RTK hilang. Tombol "Clear" menghapus seluruh track tanpa konfirmasi
   (A7, A8).

---

## A. Risiko error & kehilangan data di lapangan

### P0 — Data hilang / rusak

#### A1. Persistensi sesi tracking tidak pernah flush selama bergerak
- **Gejala lapangan:** survei 1 jam naik motor atau jalan kaki kontinu. HP membunuh app
  (RAM penuh, penghemat baterai OEM, crash). Setelah dibuka ulang, track hanya berisi titik
  sampai jeda terakhir ≥2 detik, bahkan bisa kosong.
- **Penyebab:** `TrackingPersistenceCoordinator._onChanged` membatalkan lalu membuat ulang
  `Timer(2s)` setiap kali manager memberi notifikasi (`tracking_persistence_coordinator.dart:113-115`).
  Manager memberi notifikasi pada setiap fix yang bisa direkam. Default interval 1000 ms dan
  distanceFilter 2 m (`location_config.dart`), jadi notifikasi datang tiap ~1–1,5 dtk.
  Jalur flush lain hanya `detached` (`main.dart:172`) dan reset logout. `detached` **tidak**
  dipanggil saat proses dibunuh OS.
- **Tambahan:** titik hanya hidup di memori isolate utama. Isolate background mematikan
  diri bila tidak menerima heartbeat >15 dtk (`background_tracking_service.dart:545`).
- **Rekomendasi:**
  - Ganti debounce murni dengan *throttle + max-wait*: flush paling lambat tiap 5–10 dtk
    atau tiap N titik, walau notifikasi terus datang.
  - Flush juga saat `AppLifecycleState.paused`.
  - Jangka menengah: isolate background menulis titik langsung ke SQLite (append-only)
    supaya tidak bergantung pada isolate UI.

#### A2. Restore membuang sesi & draft tanpa bertanya
- **Gejala:** surveyor mulai tracking pukul 06.00, baterai habis pukul 19.00, lalu HP
  dicas dan app dibuka. Sesi (>12 jam sejak `startedAt`) dihapus diam-diam. Hal yang sama
  terjadi bila ada >`maxConcurrent` sesi, **termasuk draft "Belum disimpan"**, padahal
  draft tidak dihitung ke batas saat app berjalan.
- **Penyebab:** `kRestoreMaxAge = 12 jam` (`tracking_persistence_coordinator.dart:9`),
  `partitionRestorable` memotong ke `maxConcurrent` tanpa membedakan draft (baris 32),
  lalu `repo.deleteSession` (baris 80).
- **Rekomendasi:** jangan pernah menghapus otomatis sesi yang punya titik. Tampilkan layar
  "Sesi tertunda ditemukan" dengan pilihan **Simpan / Lanjutkan / Buang**. Draft tidak
  dihitung ke batas.

#### A3. Pull menimpa perubahan lokal yang belum tersinkron
- **Gejala:** surveyor mengedit atribut saat offline (record jadi `isSynced=false`). Sebelum
  sempat upload, ia menekan Pull. Versi server menimpa editannya. Hal yang sama terjadi
  pada project (form lokal yang belum di-sync).
- **Penyebab:** `pullGeoDataFromServer` hanya membandingkan `updatedAt`
  (`sync_service.dart:638`) dan tidak memeriksa `existing.isSynced`. Perbandingannya pun
  antara jam server dan jam HP (rentan jam HP salah). Sama di `pullProjectsFromServer`
  (`sync_service.dart:445`).
- **Rekomendasi:** bila record lokal `isSynced == false`, jangan timpa. Tandai sebagai
  konflik dan tampilkan pilihan "pakai versi saya / versi server". Minimal: upload dulu
  sebelum pull (urutan di `performTwoWaySync` sudah benar; terapkan juga pada pull manual).

#### A4. Watermark delta maju walau record gagal disimpan → record hilang permanen
- **Gejala:** sebagian data dari tim tidak pernah muncul di HP. Pull penuh juga tidak
  membantu karena watermark sudah melewatinya.
- **Penyebab:** `maxUpdatedAt` diperbarui tepat setelah parse, **sebelum** simpan
  (`sync_service.dart:616`). Bila simpan gagal, error ditelan (`logWarn`) dan watermark
  tetap dimajukan. Pemicu nyata:
  - Kolom `collectedBy TEXT NOT NULL` (`database_service.dart:78`), padahal kontrak API
    mengizinkan `collected_by: null` (`docs/sync-delta-api-contract.md` §3). Record semacam
    ini **pasti** gagal insert.
  - `GeoPoint.fromJson` meng-assign `json['latitude']` apa adanya (`geo_data_model.dart:45`).
    Nilai integer (mis. `altitude: 0`) atau desimal-sebagai-string memicu `TypeError`.
- **Rekomendasi:**
  - Majukan watermark hanya dari record yang **berhasil** disimpan. Bila ada yang gagal,
    jangan majukan melewati `updatedAt` record gagal pertama.
  - Jadikan `collectedBy` nullable (migrasi DB v6) atau isi default `''`.
  - Gunakan `(json['x'] as num?)?.toDouble()` untuk semua angka.

#### A5. *Lost update* ketika sync berjalan bersamaan dengan edit
- **Penyebab:** setelah respons 200, `syncGeoData` menyimpan `geoData.copyWith(isSynced:true)`
  dari **snapshot awal** (`sync_service.dart:118`). Edit yang terjadi selama upload foto
  (bisa beberapa menit di sinyal lemah) tertimpa dan ikut ditandai "synced".
- **Rekomendasi:** update bersyarat
  `UPDATE ... SET isSynced=1 WHERE id=? AND updatedAt=<snapshot.updatedAt>`. Bila 0 baris
  terpengaruh, biarkan record tetap unsynced.

#### A6. Parser Emlid: format LLH/XYZ membaca kolom yang salah, dan akurasi tidak pernah terisi
- **Gejala:** memilih RTK dengan format default **LLH** memberi status "Connected", tetapi
  titik tidak pernah muncul. Sistem diam-diam kembali ke GPS HP, atau titik tidak bertambah
  pada sesi bersumber Emlid.
- **Penyebab:** format LLH/XYZ Emlid (turunan solusi RTKLIB) diawali kolom **tanggal dan jam
  GPST**, contoh `2026/09/29 10:40:54.600  -6.2088  106.8456  35.1  1  18  0.012 ...`.
  `_parseLLH` membaca `parts[0]` sebagai lintang (`location_service_v2.dart:743`), sehingga
  `double.tryParse('2026/09/29')` bernilai null dan tidak ada titik. Hal yang sama berlaku
  untuk `_parseXYZ` (baris 778). Belum ada unit test parser Emlid. Verifikasi dengan satu
  baris dari Console di layar Location Provider.
- **Tambahan:**
  - Tidak ada parser yang mengisi `accuracy`. Info card menampilkan `±N/A m`, dialog simpan
    menampilkan "unknown", dan ring akurasi di peta memakai default **15 m** walau status FIX
    2 cm.
  - GGA menyediakan HDOP (kolom 8). LLH menyediakan `sdn/sde`, sehingga akurasi horizontal
    ≈ `sqrt(sdn²+sde²)`.
- **Rekomendasi:** perbaiki indeks kolom, isi `accuracy`, dan tambahkan unit test berisi
  baris asli NMEA/LLH/XYZ.

#### A7. "Add Point" merekam titik tengah peta, bukan posisi GPS
- **Gejala:** surveyor berdiri di pohon/patok, menggeser peta sedikit untuk melihat sekitar,
  lalu menekan "Add Point". Titik tersimpan di lokasi crosshair, bukan di posisinya. Peta
  juga tidak mengikuti GPS setelah zoom awal, sehingga crosshair makin jauh dari posisi
  sebenarnya.
- **Penyebab:** `_addCurrentPoint` memakai `_mapController.camera.center`
  (`data_collection_screen.dart:1925`) dan membuat `GeoPoint` **tanpa** `accuracy`,
  `altitude`, `fixQuality`, maupun `satelliteCount`. Untuk RTK, seluruh presisi dan metadata
  hilang. Dialog konfirmasi (`_confirmSpatialAccuracy`, baris 2756) menampilkan akurasi GPS
  **saat ini**, bukan akurasi titik yang disimpan, sehingga menyesatkan.
- **Rekomendasi:** lihat B3. Sediakan tombol "Titik GPS" (dengan averaging) yang terpisah
  dari "Titik Crosshair", plus mode *follow*.

#### A8. Aksi destruktif tanpa konfirmasi
- Tombol **Clear** (`collapsible_bottom_controls.dart:318` → `_clearPoints`,
  `data_collection_screen.dart:2032`) langsung menghapus seluruh titik sesi, termasuk track
  berjam-jam. Posisinya bersebelahan dengan Undo.
- Tombol **Mode** saat tracking diam-diam memanggil `_finishTracking()`
  (`data_collection_screen.dart:3731`).
- **Rekomendasi:** Clear harus melalui dialog konfirmasi yang menyebut jumlah titik, lalu
  snackbar **Urungkan** selama 5–10 dtk. Mode toggle dinonaktifkan selama tracking, atau
  meminta konfirmasi.

#### A9. Validasi form bisa dilewati
- `_saveData` tetap menyimpan walau `validate()` gagal
  (`data_collection_screen.dart:2078`: *"Don't return - allow to continue saving"*).
- Validasi lokal tombol Simpan tidak memeriksa string kosong pada `FieldType.decimal`
  (baris 2864–2889). Akibatnya field desimal wajib yang dikosongkan tetap bisa tersimpan.
- **Rekomendasi:** `return` ketika tidak valid, scroll ke field pertama yang salah, dan
  samakan aturan validasi lokal dengan validator field.

### P1 — Gagal/macet di kondisi lapangan umum

| # | Masalah | Lokasi | Rekomendasi |
|---|---|---|---|
| A10 | **Draft form & titik manual hanya di memori.** Di HP RAM kecil, membuka kamera bisa membuat Android membunuh app. Titik (mode point/drawing) dan isian form hilang; `retrieveLostData` hanya memulihkan foto. | `_manualPoints` `data_collection_screen.dart:80`; form state | Autosave draft (titik + formData) ke SQLite setiap perubahan, lalu tawarkan pemulihan saat layar dibuka. |
| A11 | **Foto disimpan sebagai PNG** hasil encode ulang dari JPEG 85%. Ukurannya ±5–10× lebih besar (1920×1080 ≈ 3–6 MB) dan EXIF hilang. Upload berjalan 3 paralel dengan timeout 120 dtk, sehingga di 3G/EDGE upload hampir pasti timeout dan sync terus gagal. | `photo_field_widget.dart:305,504`; `photo_sync_service.dart:110`; `api_config.dart:41` | Simpan sebagai JPEG (q≈80). Upload serial atau adaptif saat sinyal lemah, dengan timeout berbasis ukuran dan progress per foto. |
| A12 | **Timeout HTTP 300 dtk** untuk semua request, termasuk login. Di sinyal 1 bar, app tampak hang hingga 5 menit. | `api_config.dart:35` | Connect ~15 dtk, request JSON ~30–60 dtk, upload terpisah. Tampilkan tombol Batal. |
| A13 | **Token 401 tidak ditangani sama sekali.** Karena logout = hapus semua data, token kedaluwarsa atau dicabut menimbulkan jalan buntu: sync gagal 401, dan logout diblokir kecuali "Hapus" (data hilang). | tidak ada handler 401 di `api_service.dart` | Tangani 401 terpusat dengan dialog **login ulang tanpa menghapus data**. Tambahkan opsi "Ekspor cadangan (ZIP)" pada dialog logout. |
| A14 | **Emlid putus tidak tersambung ulang otomatis.** Titik di bawah syarat fix (mis. FLOAT saat syarat FIX di bawah kanopi) dibuang diam-diam. Marker membeku dan tracking tidak bertambah, hanya ditandai ikon peringatan 10 px. | `location_service_v2.dart:666-676, 839` | Auto-reconnect dengan backoff. Tampilkan banner jelas, mis. "RTK FLOAT — titik tidak direkam (syarat: FIX)". |
| A15 | **Input angka:** regex hanya menerima titik (`.`) dan menolak minus. Keyboard berlokal Indonesia sering menampilkan **koma**, sehingga "2,5" ditolak diam-diam. | `dynamic_form.dart:509, 590` | Terima `,` dan `.` lalu normalisasi. Izinkan `-` opsional per field. |
| A16 | **Tipe `decimal` berubah menjadi `text` saat pull project.** `collectors` dan `defaultValue` juga hilang, karena pull menimpa project lokal dengan hasil parse yang tidak lengkap. | `_parseFieldType` `sync_service.dart:834`; `_parseProjectFromServer` | Tambah `case 'decimal'`. Parse `collectors`/`defaultValue`. Idealnya pakai `FormFieldModel.fromJson` yang sama untuk semua jalur. |
| A17 | **Parsing rapuh:** `firstWhere` tanpa `orElse` untuk `GeometryType`/`FieldType`. Satu baris korup atau tipe baru dari server menggagalkan seluruh `loadProjects()` sehingga daftar project kosong atau error. | `project_model.dart:69`, `form_field_model.dart:41`, `database_service.dart:481` | Pakai `orElse` dan isolasi per baris (try/catch per record, catat ke log). |
| A18 | **Init gagal = app macet di splash.** `AppInitializer.initialize()` melakukan `rethrow` dan tidak dibungkus try, sehingga `runApp` tidak pernah dipanggil (mis. DB tidak bisa dibuka karena storage penuh). | `main.dart:69` | Tangkap error dan tampilkan layar pemulihan (ruang penyimpanan, kirim log). |
| A19 | **Restore gagal mematikan persistensi.** Bila `restore()` melempar error, `attach()` dilewati sehingga sesi berikutnya tidak pernah di-backup. | `main.dart:76-77` | Selalu `attach()`, terpisah dari hasil restore. |
| A20 | **Tidak ada cek ruang penyimpanan.** PNG, tile offline, dan PDF basemap cepat memenuhi HP. Insert SQLite gagal dengan pesan mentah. | — | Cek ruang kosong sebelum tracking/foto/unduh tile. Peringatkan bila < ~500 MB. |
| A21 | **Tidak ada alur pengecualian optimasi baterai.** Xiaomi/Oppo/Vivo/Realme/Samsung kerap membunuh foreground service. Dialog error hanya menyebut "Disable battery optimization" tanpa tombol. | `permission_service.dart` | Minta `Permission.ignoreBatteryOptimizations` dan beri panduan per merek (lihat B1). |
| A22 | **Hapus data lokal tidak diteruskan ke server.** Record yang sudah tersinkron lalu dihapus di HP akan "hidup lagi" pada pull penuh. Dialog hapus tidak memberi tahu hal ini. | `project_detail_screen.dart:1365`, `storage_service.dart:67` | Kirim DELETE / tombstone ke server, atau jelaskan di dialog bahwa data hanya terhapus dari HP. |
| A23 | **Menggeser app keluar dari *recent apps* menghentikan tracking** (kebijakan di `detached`), padahal notifikasi service memberi kesan tracking tetap jalan. | `main.dart:172-190` | Jelaskan di UI saat Start. Tambahkan aksi "Stop" di notifikasi. Pertimbangkan opsi "tetap rekam saat app ditutup". |
| A24 | **Dialog izin background muncul setiap kali layar koleksi dibuka dan setiap Start** selama izin "Selalu" belum diberikan. Memilih "Nanti saja" saat Start **memblokir tracking**, padahal di Android foreground-service berjalan dengan izin "Saat digunakan" (sesuai komentar di `background_tracking_service.dart`). | `data_collection_screen.dart:338, 1541-1556` | Ingat pilihan user. Di Android, jangan blokir Start. Tambahkan tombol "Buka Pengaturan" (`openAppSettings` sudah ada). |

### P2 — Mutu / akurasi data

| # | Masalah | Lokasi | Rekomendasi |
|---|---|---|---|
| A25 | **Luas poligon di info card tanpa koreksi `cos(lat)`**. Nilainya berbeda dengan alat ukur peta, yang sudah benar (`measure_math.dart:37`). Selisih ±0,5–1% di Indonesia dan membesar di lintang tinggi. | `location_service_v2.dart:880-893` | Pakai `polygonAreaSqMeters` yang sama di semua tempat. |
| A26 | **Titik yang direkam adalah hasil smoothing Kalman** (Q = 3 m/dtk, tanpa model kecepatan). Sudut batas kebun bisa "terpotong", dan track kendaraan tertinggal di tikungan. | `gps_filter_pipeline.dart` (`recordable` diputuskan dari data mentah, koordinat dari Kalman) | Simpan koordinat **mentah** yang lolos gerbang. Kalman cukup untuk tampilan, atau jadikan opsi. |
| A27 | **Timestamp tanpa zona waktu.** `createdAt`/`updatedAt`, titik Emlid (`DateTime.now()`), dan payload memakai `toIso8601String()` lokal tanpa offset, sementara titik dari geolocator umumnya UTC. Contoh di kontrak API juga tanpa zona. Laporan waktu bisa bergeser 7–9 jam. | `sync_service.dart:95-104` | Kirim `toUtc().toIso8601String()` untuk semua waktu. Server menyimpan `timestamptz`. |
| A28 | **Metadata RTK tidak dikirim ke server.** `fixQuality`, `satelliteCount`, dan `speed` tidak ada di payload, sehingga QA di server tidak bisa membedakan FIX/FLOAT/HP. | `sync_service.dart:95-100` | Sertakan semua field `GeoPoint` (kontrak §3.2 sudah memuatnya). |
| A29 | **Validasi geometri minim.** Hanya jumlah titik yang diperiksa. Poligon dari tracking sering *self-intersecting* (jalan balik di sisi yang sama). Titik bisa duplikat, dan luas bisa ≈0 bila 3 titik berkumpul akibat jitter. | `session_to_geodata.dart` | Peringatkan (tanpa memblokir) bila poligon berpotongan sendiri, luas/panjang di bawah ambang, atau ada vertex duplikat. |
| A30 | **Ekspor GeoJSON:** data tanpa titik diekspor ke `[0,0]` (Null Island). Dimensi campur 2D/3D dalam satu ring. `ring.first != ring.last` membandingkan referensi List sehingga selalu menambah vertex penutup, termasuk duplikat. | `project_detail_screen.dart:517, 541` | Lewati fitur tanpa geometri. Seragamkan dimensi. Bandingkan nilai koordinat. |
| A31 | **Koordinat watermark foto** diambil dari posisi saat form dibuka, bukan saat foto diambil, dan bisa berbeda dengan titik crosshair yang disimpan. | `data_collection_screen.dart:2931-2932` | Ambil posisi saat shutter ditekan, lalu cantumkan juga koordinat titik yang disimpan. |

### P3 — Kinerja, baterai, kepatuhan

| # | Masalah | Lokasi | Rekomendasi |
|---|---|---|---|
| A32 | **Rebuild layar penuh ~60 fps.** Setiap fix memicu animasi marker 400 ms (`setState` per frame), kompas `setState` hingga 10 Hz, dan `onPositionChanged` `setState` di setiap frame geser peta. Tiap build membangun ulang **semua fitur layer impor** dari Map GeoJSON mentah. SHP besar (ribuan blok) berarti jank, HP panas, dan baterai boros. | `data_collection_screen.dart:1493, 3434-3438, 3468` | Cache hasil `_buildGeoJsonLayers` per layer/zoom. Pisahkan marker & kompas ke `ValueListenableBuilder` agar tidak me-rebuild peta. |
| A33 | **`WakelockPlus.enable()` menjaga layar tetap menyala** selama tracking, padahal layar adalah konsumen baterai terbesar. | `background_tracking_service.dart:278` | Jadikan opsi "Layar tetap menyala" (default mati). Service lokasi tidak membutuhkannya. |
| A34 | **Bulk download tile dari `tile.openstreetmap.org` (dan ArcGIS World Imagery)** dengan User-Agent generik `GeoformApp/1.0`. Kebijakan tile OSM melarang unduhan massal untuk offline. Bila diblokir, peta online maupun offline tampil kosong di lapangan. | `basemap_model.dart:190`, `tile_download_manager.dart:100` | Gunakan penyedia tile berlisensi offline (MapTiler/Mapbox/server sendiri) atau MBTiles/PDF. UA harus spesifik aplikasi dan berisi kontak. |
| A35 | **Info kritis berukuran 8–11 px**: akurasi (10), kualitas fix (8), sumber GPS (9), koordinat (11). Tidak terbaca di bawah terik matahari. | `_buildInfoCard` `data_collection_screen.dart:3809+` | Lihat B2. |

---

## B. Rekomendasi UI/UX (tanpa mengurangi fungsi)

Prinsip: di lapangan, pengguna berkeringat, memakai sarung tangan, terpapar matahari, sinyal
lemah, dan harus bekerja cepat. Informasi status harus **besar dan jelas**, aksi destruktif
harus **bisa dibatalkan**, dan pekerjaan tidak boleh hilang.

### B1. Layar "Siap ke Lapangan" (checklist pra-survei)
Satu layar dari beranda dan saat Start pertama kali per hari. Setiap baris berwarna
hijau/kuning/merah dan punya tombol perbaikan:
- Izin lokasi ("Selalu" / "Saat digunakan") → **Buka Pengaturan**
- Optimasi baterai dikecualikan → **Kecualikan** (plus panduan per merek HP)
- GPS aktif & fix terakhir (akurasi, umur)
- Ruang penyimpanan tersisa
- Basemap offline mencakup area kerja? (bounding box project vs tile tersimpan)
- Emlid tersambung & kualitas fix (bila provider RTK)
- Data/foto belum tersinkron

### B2. Panel status GPS yang terbaca di bawah matahari
Di layar koleksi, ganti baris kecil di info card dengan "pill" status besar (≥16 sp):
- **Akurasi** berukuran besar dengan warna (hijau ≤ syarat, kuning, merah)
- **Sumber & kualitas**: `HP` / `RTK FIX` / `RTK FLOAT` / `TERPUTUS`
- **Umur fix** ("2 dtk lalu"); bila >10 dtk tampilkan peringatan
- Banner merah penuh-lebar saat titik **tidak direkam** (RTK di bawah syarat, GPS basi,
  tracking dijeda). Pesannya menyebut alasan dan langkahnya.
- Tambahkan mode kontras tinggi ("Mode Luar Ruang") di Settings.

### B3. Aksi ambil titik yang eksplisit
- **"Ambil Titik GPS"** (tombol primer): rata-rata N detik atau N fix (pilihan 1/5/10 dtk),
  lalu tampilkan akurasi hasilnya sebelum disimpan. Simpan `accuracy`, `fixQuality`,
  `satelliteCount`, dan `altitude`.
- **"Titik Crosshair"** (sekunder): perilaku sekarang, untuk digitasi dari basemap.
- **Mode ikuti (follow-me)**: toggle yang otomatis memusatkan peta ke posisi. Otomatis mati
  saat user menggeser peta, dan tombol "My Location" menyalakannya kembali.
- Umpan balik **getar + bunyi** saat titik tersimpan, tracking mulai/berhenti, dan GPS
  hilang.

### B4. Kontrol bawah yang aman & mudah dijangkau
- Tombol minimal 56 dp berlabel teks + ikon. Saat panel diciutkan, tampilkan bar ringkas
  yang **tetap** berisi aksi utama (Start/Pause/Ambil Titik), bukan hanya "Swipe up for
  controls".
- **Clear**: pindahkan ke menu ⋮ dan beri konfirmasi + Urungkan. **Undo** tetap di bar
  utama.
- Tombol **Mode** dinonaktifkan selama tracking, dengan tooltip penjelasan.
- Kolom kanan saat ini berisi 7+ tombol yang menutupi peta. Kelompokkan Layers/Basemap/
  Offline ke satu tombol "Peta" (sheet). Kompas & My Location tetap terpisah.

### B5. Form yang cepat & tahan gangguan
- **Autosave draft** (lihat A10) dengan indikator "Draft tersimpan 10:42".
- Header progres "3 dari 5 wajib terisi". Tombol Simpan selalu aktif. Saat ditekan dengan
  field kosong, scroll ke field pertama yang salah dan sorot, alih-alih tombol abu-abu tanpa
  penjelasan.
- Nilai yang di-pin langsung dihitung sebagai valid saat form dibuka (sekarang tombol
  Simpan tetap nonaktif sampai ada field yang diubah).
- Keyboard angka menerima koma. Field tanggal punya tombol "Hari ini".
- Tombol **"Simpan & Titik Berikutnya"** untuk survei point beruntun: form kosong,
  pinned value tetap terisi, dan kembali ke peta tanpa keluar layar.
- Dialog konfirmasi akurasi hanya muncul bila data **di bawah syarat**. Untuk track,
  tampilkan ringkasan akurasi data (median/terburuk), bukan akurasi saat ini.

### B6. Sinkronisasi satu tombol
- Satu tombol **"Sinkronkan"** yang otomatis menjalankan project → data → foto. Sekarang
  user harus "Sync project dulu" secara terpisah.
- Antrean yang terlihat di beranda: "12 data · 30 foto menunggu". Tampilkan progres per
  foto (MB terkirim).
- Opsi **auto-sync saat Wi-Fi/online** (WorkManager/BGTask), dengan tombol manual tetap ada.
- Hasil gagal dikelompokkan dengan bahasa manusia dan tombol "Coba lagi yang gagal".

### B7. Bahasa & pesan error
- Seragamkan ke **Bahasa Indonesia**. Saat ini bercampur, mis. "Location Service Error",
  "Add Point (Center)", "Data saved successfully" berdampingan dengan "Nanti saja" dan
  "Gagal memuat gambar".
- Jangan tampilkan exception mentah (`'Error: $e'`, `Connection error: SocketException…`).
  Petakan ke pesan + tindakan, mis. "Tidak ada sinyal ke server. Data aman tersimpan di HP."
  dengan tombol [Coba lagi].

### B8. Beranda sebagai dasbor lapangan
Di atas grid 9 menu, tampilkan kartu status: tracking aktif, data belum sync, ruang
penyimpanan, dan status basemap offline. Kelompokkan menu:
- **Survei**: Projects, Layers, Basemaps
- **Alat**: Navigation, Analysis Report
- **Akun**: Notifications, Profile, Settings, Location

### B9. Koreksi geometri
Edit sekarang hanya untuk atribut. Tambahkan edit vertex (geser/hapus/sisip) dengan
tampilan urutan vertex, sehingga titik yang salah tidak perlu dihapus dan diambil ulang di
lokasi.

---

## C. Urutan pengerjaan yang disarankan

| Sprint | Isi | Alasan |
|---|---|---|
| **1 (P0, perubahan kecil)** | A1 throttle flush · A2 kebijakan restore · A4 watermark + `collectedBy` nullable · A3 jangan timpa unsynced · A8 konfirmasi Clear · A9 stop saat invalid · A6 parser Emlid + test | Menutup semua jalur kehilangan data. Sebagian besar perubahan < 50 baris. |
| **2 (P1)** | A11 JPEG + upload adaptif · A12 timeout · A13 login ulang tanpa hapus · A10 autosave draft · A15 koma desimal · A16/A17 parsing · A18/A19 init & restore | Menghilangkan kegagalan sync dan crash di HP murah / sinyal lemah. |
| **3 (UX)** | B1–B3 (checklist, status GPS, titik GPS vs crosshair) · B4 kontrol · B7 bahasa | Dampak UX terbesar untuk surveyor. |
| **4** | B5, B6, B8, B9 · A25–A35 | Penyempurnaan & mutu data. |

---

## D. Skenario uji lapangan (untuk Checkpoint)

1. Tracking naik motor 15 menit tanpa berhenti → `adb shell am kill` / force-stop → buka
   ulang: jumlah titik ≈ sebelum kill (selisih ≤ 10 dtk).
2. Mulai tracking, matikan HP 13 jam, lalu nyalakan: sesi muncul di layar pemulihan, tidak
   hilang.
3. Edit atribut saat offline → Pull → editan tetap ada (atau muncul dialog konflik).
4. Server mengirim record dengan `collected_by: null` → record tersimpan. Pull delta
   berikutnya tidak melewatkannya.
5. Emlid format LLH, NMEA, dan XYZ: titik tampil dengan akurasi terisi. Cabut Wi-Fi Emlid
   30 dtk → otomatis tersambung lagi dan muncul banner.
6. Keyboard Samsung/Gboard berlokal Indonesia: input "2,5" pada field desimal tersimpan
   2.5.
7. HP RAM 2–3 GB (Android Go): isi form → buka kamera → app dibunuh → kembali: titik, isian
   form, dan foto pulih.
8. Sinyal EDGE / throttling 64 kbps: sync 10 data × 3 foto selesai atau gagal dengan pesan
   jelas, tanpa hang >60 dtk.
9. Token dicabut di server → sync menampilkan dialog login ulang, data lokal tetap utuh.
10. Xiaomi/Oppo dengan penghemat baterai aktif, layar mati 30 menit saat tracking →
    track tidak terputus (atau user diperingatkan di checklist B1).
11. Storage < 200 MB → app memberi peringatan sebelum tracking/foto, dan tidak macet di
    splash.

---

## E. Status implementasi (29 Sep 2026)

Legenda: ✅ selesai · ◐ sebagian (lihat catatan) · — tidak diubah (keputusan pemilik produk).
Seluruh teks UI kini berbahasa **Inggris** sesuai keputusan pemilik produk (B7 semula
menyarankan Bahasa Indonesia). Komentar kode tetap berbahasa Indonesia sesuai konvensi repo.

### A. Risiko error & kehilangan data

| # | Status | Implementasi | Commit |
|---|---|---|---|
| A1 | ✅ | `TrackingPersistenceCoordinator`: flush debounce 2 dtk, maks 8 dtk; flush saat app ke background; gagal per sesi diisolasi & dicatat. | 46baac0 |
| A2 | ✅ | Restore hanya membuang sesi tanpa titik; sesi lama (>12 jam) / melebihi batas diturunkan jadi draft "Not saved". | 46baac0 |
| A3 | ✅ | Pull tidak menimpa record lokal yang belum tersinkron (dihitung sebagai konflik). | 0bf5511 |
| A4 | ✅ | `PullWatermarkTracker`: watermark hanya maju sejauh record yang tuntas. | 0bf5511 |
| A5 | ✅ | `saveGeoDataIfUnchanged` (UPDATE bersyarat `updatedAt`) saat menandai tersinkron. | 0bf5511 |
| A6 | ✅ | Parser LLH/XYZ/NMEA baru (`emlid_parsers.dart`), akurasi dari sdn/sde, sigma ECEF, atau GST/HDOP. | 15d09e5 |
| A7 | — | Add Point tetap di crosshair (disengaja). Untuk posisi GPS: tombol *My location* kini menyalakan mode ikuti (B3). | 7b2ede5 |
| A8 | ✅ | Clear titik dengan konfirmasi + Undo; buang sesi dengan konfirmasi; dialog hapus menjelaskan salinan server; logout wajib ketik `DELETE`. | e66172f, 9210fb0 |
| A9 | ✅ | `formFieldIssues` memblokir simpan (koleksi, sheet tracking, edit record) dan menggulir ke field bermasalah. | e66172f, 7b2ede5 |
| A10 | ✅ | `CollectionDraftService`: titik & isian form di-autosave per project dan dipulihkan. | e66172f |
| A11 | ✅ | Foto JPEG (tanpa watermark = salinan asli), upload paralel 2, timeout sesuai ukuran. | 1a7a332 |
| A12 | ◐ | Login 30 dtk, request 90 dtk, upload 60–600 dtk sesuai ukuran. Belum ada tombol Batal saat sync (progres ditampilkan). | 0bf5511, 1a7a332 |
| A13 | ✅ | 401 → dialog login ulang user yang sama (data tetap); "Later" menunda 10 menit. Cadangan ZIP dari dialog logout & Settings. | 9210fb0 |
| A14 | ✅ | Reconnect otomatis (2→30 dtk) + watchdog 30 dtk; titik di bawah syarat ditandai & tampil sebagai banner. | 15d09e5, e66172f |
| A15 | ✅ | Input angka menerima koma & minus (`parseLocaleNumber`). | e66172f |
| A16 | ✅ | Pull mempertahankan tipe `decimal`, `defaultValue`, dan `collectors`. | 0bf5511 |
| A17 | ✅ | Parsing toleran (`json_parse.dart`), tipe tak dikenal → fallback, baris rusak diisolasi. | 0bf5511 |
| A18 | ✅ | Init gagal → layar pemulihan (Try again + bagikan log). | 8d81d9e |
| A19 | ✅ | Persistensi selalu terpasang walau restore gagal. | 46baac0 |
| A20 | ✅ | Cek ruang kosong sebelum tracking/foto/unduh tile; pesan "storage full" yang jelas. | 8d81d9e, 963a91c |
| A21 | ✅ | Butir baterai di checklist dengan tombol + panduan per merek; ditanyakan pada Start pertama tiap hari. Memakai layar daftar optimasi (tanpa izin `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, aman untuk kebijakan Play). | deb38eb |
| A22 | ◐ | Dialog hapus menjelaskan bahwa salinan yang sudah tersinkron tetap di server. DELETE/tombstone ke server butuh dukungan API. | 0bf5511 |
| A23 | ◐ | Peringatan saat Start + butir "While tracking" di checklist. Aksi "Stop" di notifikasi belum dibuat (butuh uji perangkat untuk aksi lintas-isolate). | e66172f, deb38eb |
| A24 | ✅ | Pilihan penjelasan izin diingat; di Android "Not now" tidak memblokir Start; tombol *Open settings*. | e66172f |
| A25 | ✅ | Semua luas memakai `polygonAreaSqMeters`. | 15d09e5 |
| A26 | ✅ | Titik jalur = koordinat mentah yang lolos gerbang; Kalman hanya untuk marker (bisa diubah di GPS settings). | 963a91c |
| A27 | ✅ | Semua waktu di payload, JSON, dan ekspor dikirim UTC. | 0bf5511, 66479db |
| A28 | ✅ | `fixQuality`, `satelliteCount`, `speed` ikut dikirim. | 0bf5511 |
| A29 | ✅ | Peringatan poligon berpotongan, luas ≈0, vertex ganda, garis pendek (juga di editor geometri). | e66172f, 7b2ede5 |
| A30 | ✅ | `GeoExport`: record tanpa geometri dilewati & dilaporkan, ring ditutup berdasar nilai, dimensi seragam, aman NaN. | 66479db |
| A31 | ✅ | Koordinat watermark diambil saat shutter. | 1a7a332 |
| A32 | ✅ | Marker/kompas/koordinat lewat notifier (tanpa rebuild layar penuh), layer GeoJSON di-cache; kebocoran timer DNS `ConnectivityService` diperbaiki. | e66172f, deb38eb |
| A33 | ✅ | "Keep screen on while tracking" opsional (default mati), berlaku langsung. | 963a91c |
| A34 | ◐ | User-Agent spesifik + kontak, peringatan kebijakan tile OSM & cek ruang sebelum unduh massal. Pergantian ke penyedia tile berlisensi offline adalah keputusan bisnis. | 963a91c, 66479db |
| A35 | ✅ | Info GPS besar (akurasi 22 sp) dan banner status. | e66172f |

### B. UI/UX

| # | Status | Implementasi | Commit |
|---|---|---|---|
| B1 | ✅ | Layar **Ready for the field** (izin, GPS & fix, Emlid, baterai, notifikasi, penyimpanan, peta offline di posisi saat ini, data belum sync, track belum disimpan) dengan tombol perbaikan per butir. | deb38eb |
| B2 | ◐ | Banner status GPS & akurasi besar. Mode kontras tinggi ("Outdoor mode") belum dibuat. | e66172f |
| B3 | ◐ | Mode ikuti (*My location*) + getar. Tombol "Take GPS point" dengan perataan tidak dibuat karena Add Point di crosshair adalah perilaku yang diinginkan. | 7b2ede5 |
| B4 | ◐ | Bar ringkas berisi aksi utama, tombol 52 dp, Clear dengan konfirmasi + Undo, Mode nonaktif saat tracking. Tombol peta di kolom kanan belum digabung jadi satu tombol "Map". | e66172f |
| B5 | ◐ | Autosave draft (dipulihkan saat layar dibuka), progres field wajib, Simpan selalu aktif + gulir ke field, pinned value langsung valid, koma, "Today", "Save & next", konfirmasi akurasi hanya bila di bawah syarat. Indikator "Draft saved 10:42" belum ditampilkan. | e66172f |
| B6 | ◐ | Satu tombol Sync (project → data → foto), antrean di beranda & detail project, "Retry failed", auto-sync saat online (selama app terbuka). Progres MB per foto belum ada. | deb38eb |
| B7 | ✅ | Semua UI berbahasa Inggris; tak ada lagi exception mentah — `loggedErrorMessage()` mencatat detail ke log diagnostik dan menampilkan kalimat ramah. | 88deec6 |
| B8 | ✅ | Beranda = dasbor lapangan (tracking aktif, kesiapan, antrean sync) + menu berkelompok Survey / Tools / Account & device. | deb38eb |
| B9 | ✅ | Editor geometri berbasis crosshair: pilih/geser/sisip/hapus vertex, undo/reset, daftar vertex, garis asli putus-putus. | 7b2ede5 |

### Verifikasi

- `flutter analyze`: 0 error, tidak ada warning baru dibanding baseline (42 warning lama).
- `flutter test`: 583 lulus, 0 gagal. Tes sheet data jalan (`routing_data_manager_test.dart`)
  yang sebelumnya selalu gagal di host desktop kini menyetel ketersediaan routing secara
  eksplisit dan mencakup ketiga kondisi sheet serta dialog platform tak didukung.
- Plugin Kotlin `DeviceHealthPlugin` dikompilasi terhadap `android.jar`; kode Swift (iOS) belum
  dikompilasi (tidak ada toolchain iOS di lingkungan ini).
- Belum diuji di perangkat. Skenario uji lapangan di bagian D perlu dijalankan di HP (terutama
  kill/restore tracking, Emlid putus-sambung, optimasi baterai per merek, dan sync di sinyal lemah).
