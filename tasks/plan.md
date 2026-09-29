# Rencana: Nama Basemap Analysis + Import Layer SHP/GPX/XML + Reset App saat Logout

Status: **DISETUJUI user (2026-09-29) — semua default Open Questions diterima** · Tanggal: 2026-09-29 · Branch: `main` (commit per task)
Plan sebelumnya (basemap PDF, selesai): [plan-basemap-pdf.md](plan-basemap-pdf.md)

## Overview
Tiga fitur independen:
1. **Nama basemap dari Analysis Report** — sekarang hanya `file.title`
   ([analysis_files_screen.dart:174](../lib/screens/analysis/analysis_files_screen.dart)).
   Diberi prefix **project** = level pertama Analysis Report (`AnalysisType.name`, alurnya
   Project → Perusahaan → Berkas), mis. `Project Replanting · NDVI Blok A12`.
2. **Import layer** — halaman Layers hanya menerima `.json/.geojson`
   ([layers_screen.dart:57](../lib/screens/layers/layers_screen.dart)). Ditambah **SHP ber-zip,
   GPX, dan XML (KML)**. Semua dikonversi ke GeoJSON saat import → sisa pipeline (simpan, style,
   render di 3 layar peta) tak berubah.
3. **Reset app saat logout** — `AuthService.logout()` hanya menghapus token & user
   ([auth_service.dart:175](../lib/services/auth_service.dart)); project, data, foto, basemap,
   layer, sesi tracking, cache, dan log user sebelumnya tetap ada untuk user berikutnya.

## Architecture Decisions
- **(1) Helper murni `analysisBasemapName(project, title)`** — tak dobel prefix bila judul sudah
  diawali nama project; dipakai juga di dialog progres & snackbar.
- **(2) `LayerImporter`: satu pintu import → GeoJSON** (deteksi format dari ekstensi + isi).
  Konverter murni per format (teruji dengan fixture kecil), parsing di isolate (`compute`) agar
  berkas besar tak membekukan UI. Konverter GPX/KML memakai paket **`xml`** (lihat Open Question 4).
  SHP dibaca sendiri (format biner .shp/.dbf sederhana, tanpa paket baru) + reproyeksi
  **WGS84 geografis & UTM WGS84 (zona N/S)** dari `.prj`; proyeksi lain ditolak dengan pesan jelas.
- **(3) `AppResetService`: "hapus semua kecuali allowlist"** (default-deny keep), bukan daftar
  yang harus dirawat: seluruh isi folder Documents/Support/Temp app + semua database SQLite
  dihapus, SharedPreferences dikosongkan lalu hanya kunci perangkat di allowlist yang
  dipulihkan. Storage baru di masa depan otomatis ikut terhapus.
- **Urutan reset wajib:** hentikan tracking (engine, service, sesi) → hentikan sync/unduhan →
  tutup koneksi DB → hapus berkas/DB → reset singleton in-memory & cache gambar → logout auth
  (FCM cleanup yang sudah ada) → layar login.
- **Pengaman kehilangan data:** sebelum reset, hitung data belum tersinkron (project, geo data,
  foto) + sesi tracking aktif. Ada → dialog **Sync dulu / Batal / Hapus & Logout** (yang terakhir
  butuh konfirmasi ketik `HAPUS`).

## Dependency Graph
```
(1) T1 analysisBasemapName ─► wiring AnalysisFilesScreen                      [mandiri]

(2) T2 LayerImporter (dispatch + GeoJSON lama) ─┬─► T3 GPX
                                                ├─► T4 KML/XML (+KMZ)
                                                └─► T5 SHP reader ─► T6 .prj/UTM + zip + wiring

(3) T7 cek data belum sync + dialog logout ─► T8 AppResetService (wipe + allowlist)
                                           ─► T9 reset singleton + uji "user B tak lihat data A"
```

## Task List

### Phase 1 — Nama basemap Analysis Report
#### T1: Prefix project pada nama basemap dari Analysis Report (S)
- AC: basemap baru bernama `"<project> · <judul>"` dengan project = `AnalysisType.name` (diteruskan AnalysisCompaniesScreen → AnalysisFilesScreen sebagai parameter baru `projectName`); tak dobel bila judul sudah berawalan nama project; nama kosong/spasi dirapikan; dialog progres & snackbar memakai nama yang sama.
- Verifikasi: unit test helper; widget/manual: tambah PDF dari Analysis Report → nama di pemilih basemap & Kelola Basemap lengkap.
- Files: `lib/services/analysis/analysis_basemap_name.dart` (baru), `lib/screens/analysis/analysis_files_screen.dart`, `lib/screens/analysis/analysis_companies_screen.dart`, test.

### Checkpoint 1
- [ ] Test hijau; nama basemap tampil lengkap di pemilih basemap.

### Phase 2 — Import layer SHP (zip), GPX, XML
#### T2: `LayerImporter` — satu pintu import, GeoJSON lama tetap jalan (S–M)
- AC: deteksi format (`.json/.geojson`, `.zip`, `.gpx`, `.kml/.kmz/.xml` — XML diendus dari elemen root `<gpx>`/`<kml>`); format tak dikenal → pesan jelas daftar format yang didukung; hasil = GeoJSON FeatureCollection + nama default; parsing di isolate. Layers screen memakai importer (perilaku GeoJSON identik).
- Verifikasi: unit test dispatch + regresi GeoJSON; analyze.
- Files: `lib/services/layer_import/layer_importer.dart` (baru), `lib/screens/layers/layers_screen.dart`, test.

#### T3: GPX → GeoJSON (S)
- AC: `wpt` → Point, `trk/trkseg` → LineString/MultiLineString, `rte` → LineString; properti `name/desc/ele/time`; GPX tanpa geometri → error jelas.
- Verifikasi: unit test fixture GPX kecil (waypoint + track 2 segmen + route).
- Files: `lib/services/layer_import/gpx_converter.dart`, test + fixture.

#### T4: KML / XML (+ KMZ) → GeoJSON (S–M)
- AC: `Placemark` Point/LineString/Polygon (termasuk lubang/innerBoundary) & MultiGeometry; properti `name/description/ExtendedData`; Folder bersarang; `.kmz` = zip berisi `doc.kml`.
- Verifikasi: unit test fixture KML (polygon berlubang, MultiGeometry, ExtendedData) + KMZ.
- Files: `lib/services/layer_import/kml_converter.dart`, test + fixture.

#### T5: Pembaca Shapefile (.shp + .dbf) (M)
- AC: tipe Point/MultiPoint/PolyLine/Polygon (+ varian Z/M, diambil XY); polygon multi-ring dipisah jadi outer/hole berdasar arah putaran → Polygon/MultiPolygon; atribut `.dbf` (C/N/F/L/D) dengan encoding dari `.cpg` (default UTF-8, fallback Latin-1); record null dilewati.
- Verifikasi: unit test dengan shapefile fixture kecil (dibuat oleh test/generator) tiap tipe geometri + atribut.
- Files: `lib/services/layer_import/shapefile_reader.dart`, `lib/services/layer_import/dbf_reader.dart`, test + fixture.

#### T6: SHP ber-zip — proyeksi `.prj` + wiring (M)
- AC: zip dibongkar di memori; wajib ada `.shp/.shx/.dbf` (pesan jelas bila kurang); `.prj` WGS84 geografis → apa adanya, UTM WGS84 zona N/S → dikonversi ke lat/lon (galat < 1 m), proyeksi lain/tanpa `.prj` dengan koordinat bukan derajat → ditolak dengan pesan; zip berisi >1 shapefile → user memilih satu.
- Verifikasi: unit test konversi UTM (titik acuan zona 48S/49S/50S/51N), test zip lengkap/kurang; manual: import SHP kebun dari lapangan tampil di posisi benar.
- Files: `lib/services/layer_import/prj_projection.dart`, `lib/services/layer_import/zipped_shapefile.dart`, `layer_importer.dart`, test.

### Checkpoint 2
- [ ] Test hijau; device: import 1 contoh tiap format (GeoJSON, SHP zip UTM, GPX, KML, KMZ) → tampil di Layers & 3 layar peta pada posisi benar, tanpa macet.

### Phase 3 — Reset app saat logout
#### T7: Pengaman data belum tersinkron saat logout (S)
- AC: logout menghitung project/geo data/foto belum sync + sesi tracking aktif; jika ada → dialog berisi jumlahnya dengan **Sync dulu** (jalankan sync, lalu kembali ke dialog), **Batal**, **Hapus & Logout** (ketik `HAPUS`). Tanpa data tertunda → konfirmasi biasa yang menjelaskan semua data di HP akan dihapus.
- Verifikasi: widget test dialog (hitungan, tombol hapus nonaktif sebelum `HAPUS` diketik).
- Files: `lib/services/app_reset/logout_guard.dart` (baru), `lib/screens/menu_screen.dart`, test.

#### T8: `AppResetService` — hapus semua kecuali allowlist (M)
- AC: urutan: stop TrackingEngine/service & buang sesi → hentikan sync/unduhan → tutup DB (utama + cache tile) → hapus semua DB di folder database app + seluruh isi Documents/Support/Temp → SharedPreferences dikosongkan lalu kunci allowlist perangkat dipulihkan → cache gambar dikosongkan. Kegagalan satu langkah dicatat & langkah berikutnya tetap jalan; ringkasan hasil ke log.
- Verifikasi: unit test dengan folder temp & fake: semua berkas/DB terhapus, allowlist tersisa, urutan (engine berhenti sebelum DB ditutup).
- Files: `lib/services/app_reset/app_reset_service.dart` (baru), `lib/services/auth_service.dart`, `lib/services/database_service.dart`, `lib/services/tile_cache_sqlite_service.dart` (tutup koneksi), test.

#### T9: Reset state in-memory + uji "user B tak melihat data user A" (M)
- AC: singleton yang meng-cache data (DatabaseService, TileCacheSqliteService, TrackingSessionManager, BasemapService/Settings cache, SyncWatermark, notifikasi, PdfOverlay/Image cache, user Crashlytics) dikosongkan; setelah reset app kembali ke login tanpa restart; login user lain → daftar project/layer/basemap/notifikasi kosong.
- Verifikasi: test integrasi service-level (isi data → reset → semua query kosong); manual: logout A → login B.
- Files: service terkait (`reset()` kecil per singleton), `app_reset_service.dart`, test.

### Checkpoint 3 — Complete
- [ ] `flutter test` hijau (kecuali 2 kegagalan lama); `flutter analyze` 0 error.
- [ ] Device: user A (ada data, 1 belum sync) → logout diblokir dialog → Sync dulu → logout → login user B → tak ada data A (project, foto, layer, basemap PDF, sesi tracking, log).

## Risks and Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Logout menghapus data lapangan yang belum tersinkron | **High** | T7: blokir + tampilkan jumlah + "Sync dulu"; hapus paksa butuh ketik `HAPUS` |
| Reset sebagian (singleton masih memegang data/DB terbuka) | High | Hapus-semua-kecuali-allowlist + T9 uji "user B kosong"; tutup DB sebelum hapus |
| Tracking/service masih jalan saat berkas dihapus | Med | Urutan wajib: engine & service berhenti paling awal |
| SHP dengan proyeksi selain WGS84/UTM (mis. TM-3 lokal) | Med | Ditolak dengan pesan jelas (bukan salah posisi diam-diam); proyeksi tambahan jadi task lanjutan |
| Berkas SHP/KML besar membekukan UI | Med | Parsing di isolate (`compute`), batas ukuran + pesan |
| Menambah paket `xml` ke `pubspec.yaml` yang punya perubahan lokal user | Low | Minta izin (OQ4); hanya menambah 1 baris dependency |

## Keputusan (Open Questions — default diterima saat approve)
1. **"Project" = level pertama Analysis Report (`AnalysisType.name`)** — dikoreksi user (bukan `compName`). Format `"<Project> · <judul>"`. Basemap lama tidak diganti namanya.
2. **"XML" = KML?** Usul: terima `.kml`, `.kmz`, dan `.xml` (isi diendus: root `<kml>` atau `<gpx>`); XML lain ditolak.
3. **SHP:** proyeksi yang didukung WGS84 + UTM WGS84 (umum di data kebun Indonesia); zip berisi beberapa shapefile → user memilih satu. *(usul: ya)*
4. **Dependency `xml` ditambahkan ke `pubspec.yaml`** (sesuai Architecture Decision yang di-approve) — hanya satu baris itu; perubahan lokal user di pubspec tidak ikut di-commit.
5. **Yang dipertahankan saat logout (allowlist):** setelan tampilan & satuan, setelan GPS & Emlid (milik perangkat, bukan user). **Dihapus:** semua data user, basemap PDF, layer, data jalan, cache tile (termasuk OSM offline), notifikasi, sesi tracking, log diagnostik. *(usul: ya — cache tile OSM ikut dihapus demi "kondisi awal")*
