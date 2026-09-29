# Rencana: Perbaikan Basemap PDF (macet / tidak muncul saat ganti PDF)

Status: **disetujui user ("langsung perbaiki") — /build auto** · Tanggal: 2026-09-29 · Branch: `main`
Sumber: review basemap PDF (Critical 1–2, Important 3–4, rekomendasi 1–5).
Plan sebelumnya (sistem log, selesai): [plan-logging.md](plan-logging.md)

## Akar masalah
1. **Macet:** `_buildBasemapLayers` di DataCollectionScreen membaca SELURUH `overlay.png`
   (`readAsBytesSync`) + `existsSync` di SETIAP build, padahal layar rebuild tiap frame
   (animasi marker, geser peta, kompas).
2. **Tidak muncul:** ganti basemap tak memindahkan kamera → PDF di area lain berada di luar layar.
3. Overlay di-decode resolusi penuh (A1@200 DPI ≈ 124 MB RAM), gambar lama tak dilepas, dan
   `gaplessPlayback: true` menampilkan PDF lama di batas PDF baru selama decode.
4. PDF mode tile (`sqlite://`): `urlTemplate` sama-sama `''` → flutter_map 7 tak memuat ulang tile.
5. (iOS) path overlay absolut basi setelah update app → diam-diam jatuh ke OSM.

## Architecture Decisions
- **Siapkan overlay sekali saat basemap berubah, bukan di build.** `resolvePdfOverlay()` (async:
  cek berkas, bounds, pulihkan path `<documents>/basemaps/<id>/overlay.png`) → `PdfOverlaySpec`
  berisi `ResizeImage(FileImage, ≤4096 px, fit)`.
- **Satu `PdfOverlayController` dipakai 3 layar** (data collector, navigasi, notification map):
  resolve → evict gambar lama → warm-up decode (+ log durasi) → status `loading`; hasil basi
  (user ganti lagi sebelum selesai) diabaikan.
- **Satu builder layer bersama** `buildBasemapLayers()` tanpa I/O: overlay diberi
  `ValueKey(basemap.id)` + `gaplessPlayback: false`; TileLayer diberi `ValueKey(basemap.id)`
  agar ganti PDF mode tile selalu memuat ulang. Chip "Memuat peta PDF…" selama decode.
- **Kamera:** saat ganti ke PDF yang TIDAK beririsan dengan tampilan → `fitCamera` ke batas PDF;
  bila sudah terlihat, kamera dibiarkan (user mungkin sedang bekerja di area itu).
- Tanpa dependency baru; `pubspec.yaml` tak disentuh.

## Tasks
- [ ] **T1 — `resolvePdfOverlay` + helper bounds/kamera** (S) — tes berkas temp: spec, ResizeImage ≤4096 fit, pemulihan path, issue fileMissing/invalidBounds, `shouldFitToPdf`.
- [ ] **T2 — `PdfOverlayController`** (S) — tes: loading→siap, evict gambar lama saat ganti, hasil basi diabaikan, masalah → pesan.
- [ ] **T3 — `buildBasemapLayers` + chip loading** (S) — tes: key per basemap, gapless off, spec tak cocok → hanya fallback, 2 PDF tile → key beda.
- [ ] **T4 — DataCollectionScreen** (M) — pakai controller + builder, hapus I/O & log di build, fit kamera saat ganti; tes penjaga: tak ada `readAsBytesSync`/`existsSync` di jalur layer.
- [ ] **T5 — Navigasi & Notification Map** (M) — pakai controller + builder, fit kamera saat ganti.

## Checkpoint
- [ ] `flutter test` hijau (kecuali 2 kegagalan lama); `flutter analyze` 0 error.
- [ ] Device: ganti PDF A → B (area berbeda & sama) berulang kali: tak macet, kamera pindah bila perlu, tak ada PDF lama di posisi baru; Share Logs memuat baris `BASEMAP` (durasi decode).

## Di luar scope (dicatat)
- Membatasi resolusi `overlay.png` saat import (DPI/ukuran berkas) — decode sudah dibatasi 4096 px.
