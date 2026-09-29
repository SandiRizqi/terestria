# TODO — Perbaikan Basemap PDF

Plan: [plan.md](plan.md) · Plan sebelumnya: [plan-logging.md](plan-logging.md) · Branch: `main`

- [x] **T1 — `resolvePdfOverlay` + helper bounds/kamera** (S) ✅ 10 test
- [x] **T2 — `PdfOverlayController`** (S) ✅ 9 test
- [x] **T3 — `buildBasemapLayers` + chip loading** (S) ✅ 6 test
- [x] **T4 — DataCollectionScreen: tanpa I/O di build + fit kamera saat ganti** (M) ✅ 2 test penjaga (lolos uji mutasi)
- [x] **T5 — Navigasi & Notification Map** (M) ✅ helper kamera bersama (1 test widget) + penjaga 3 layar

### Checkpoint
- [x] Test hijau: 413 lulus (2 kegagalan lama); analyze 0 error
- [ ] Device: ganti PDF A → B berulang: tak macet, kamera pindah bila PDF di luar layar, Share Logs berisi baris `BASEMAP`
