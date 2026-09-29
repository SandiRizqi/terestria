# TODO — Sistem Log Diagnostik + Hapus print()

Plan: [plan.md](plan.md) · Plan sebelumnya: [plan-tracking-engine.md](plan-tracking-engine.md) · Branch: `main`

## Phase 1 — Fondasi logger
- [x] **Task 1 — Inti logger berkas** (S–M) ✅ 12 test — format, redaksi rahasia, buffer, rotasi harian, prune 7 hari/5 MB
- [x] **Task 2 — Sambung logger ke app & isolate + state Mode Diagnostik** (M) ✅ 7 test — konsol hanya debug; `bg-*.log` dari isolate; FlutterError → log

### Checkpoint A
- [ ] Test hijau; berkas `app-*.log` & `bg-*.log` muncul saat tracking

## Phase 2 — Isi log & ekspor
- [x] **Task 3 — Event tracking + ringkasan per menit** (M) ✅ 6 test — SESSION/ENGINE/SERVICE/GPS, alasan `stopSelf`
- [x] **Task 4 — Settings "Log Diagnostik"** (M) ✅ 6 test — toggle 24 jam, ukuran log, Bagikan, Hapus
- [x] **Task 5 — Paket ekspor zip** (M) ✅ 5 test — log app+bg, 3 CSV GPS, info.txt, snapshot.txt → share
- [x] **Task 6 — Breadcrumb Crashlytics** (S) ✅ 5 test — warn/error → breadcrumb; rate-limit recordError

### Checkpoint B
- [ ] Device: Mode Diagnostik ON → tracking 5 menit → Bagikan Log → zip berisi event + ringkasan

## Phase 3 — Hilangkan print()
Hitung ulang (parser): **443 panggilan di 41 file** (plan awal ±370/34 menghitung per baris).
- [x] **Task 7a — Tracking, data collection & inti app** (M) ✅ 135 panggilan: data_collection_screen, main, app_initializer, gps_logger, location_provider, notification_service, settings_service, routing_service
- [x] **Task 7b — Sync, auth, cloud, notifikasi, update** (M) ✅ 159 panggilan; token FCM & body respons token disamarkan
- [ ] **Task 7c — Basemap, tile, PDF** (M)
- [ ] **Task 7d — Sisa UI + gerbang `avoid_print: error` + test no-print** (M)

### Checkpoint C
- [ ] `flutter test` hijau (kecuali 2 kegagalan lama); analyze 0 error; release tanpa spam print

## Keputusan default
Koordinat lengkap · Mode Diagnostik 24 jam · retensi 7 hari/5 MB · release tulis info+ ke berkas
