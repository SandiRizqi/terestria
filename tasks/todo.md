# TODO — Nama Basemap Analysis + Import SHP/GPX/XML + Reset saat Logout

Plan: [plan.md](plan.md) · Plan sebelumnya: [plan-basemap-pdf.md](plan-basemap-pdf.md) · Branch: `main`

## Phase 1 — Nama basemap Analysis Report
- [x] **T1 — Prefix project pada nama basemap** (S) — `"<project> · <judul>"`, project = `AnalysisType.name`, tak dobel prefix

### Checkpoint 1
- [ ] Test hijau; nama basemap lengkap di pemilih basemap

## Phase 2 — Import layer SHP (zip), GPX, XML
- [x] **T2 — `LayerImporter` satu pintu** (S–M) — deteksi format, GeoJSON lama tetap jalan, parsing di isolate
- [x] **T3 — GPX → GeoJSON** (S) — wpt/trk/rte + properti
- [x] **T4 — KML/XML (+KMZ) → GeoJSON** (S–M) — Placemark, polygon berlubang, MultiGeometry
- [ ] **T5 — Pembaca Shapefile .shp + .dbf** (M) — semua tipe geometri, atribut, encoding `.cpg`
- [ ] **T6 — SHP ber-zip: `.prj` WGS84/UTM + wiring** (M) — tolak proyeksi lain, pilih bila >1 shapefile

### Checkpoint 2
- [ ] Device: import GeoJSON, SHP zip (UTM), GPX, KML, KMZ → posisi benar di 3 layar peta

## Phase 3 — Reset app saat logout
- [ ] **T7 — Pengaman data belum sync** (S) — dialog jumlah + Sync dulu / Batal / Hapus (ketik `HAPUS`)
- [ ] **T8 — `AppResetService`** (M) — hapus semua kecuali allowlist, urutan aman
- [ ] **T9 — Reset state in-memory + uji user B** (M) — tak ada data user A setelah login ulang

### Checkpoint 3
- [ ] Test hijau; analyze 0 error; device: logout A (ada data belum sync) → login B bersih

## Open questions (lihat plan.md)
1. Project = `AnalysisType.name` (level pertama; dikoreksi user)  2. XML = KML (+ .kmz)?  3. SHP: WGS84 + UTM saja?
4. Boleh tambah dependency `xml` di pubspec?  5. Allowlist logout: setelan tampilan/GPS/Emlid saja?
