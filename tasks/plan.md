# Rencana: Sistem Log Diagnostik (in-app, bisa diekspor) + Hapus print()

Status: **DRAFT — menunggu review**
Tanggal: 2026-09-29 · Branch: `main` (commit per task)
Plan sebelumnya (TrackingEngine, selesai): [plan-tracking-engine.md](plan-tracking-engine.md)

## Overview
Log tracking saat ini tidak bisa diperiksa di lapangan. Penyebabnya:
- `logDebug()` diam di build release.
- Ada ±370 `print`/`debugPrint` di 34 file yang hanya masuk logcat dan hilang saat app ditutup.
- Log dari isolate background tidak tersimpan di mana pun.

Yang dibangun:
- **Log berkas bergulir** di HP: berlevel dan bertag, dari app maupun isolate background.
- **Mode Diagnostik** untuk log detail, mati otomatis setelah 24 jam.
- Tombol **Bagikan Log**: zip berisi log, info perangkat, dan kondisi tracking saat itu, dikirim lewat share sheet.
- Warn/error diteruskan ke Crashlytics sebagai breadcrumb.

Terakhir, **semua `print()`/`debugPrint()` di `lib/` diganti logger**, dan larangannya dikunci dengan lint serta test.

## Architecture Decisions
- **Satu logger, API tetap.** `logDebug`/`logInfo`/`logWarn`/`logError(msg, {tag})` di [app_logger.dart](../lib/utils/app_logger.dart), sehingga pemanggil lama (7 file tracking) otomatis ikut.
  - Konsol hanya di build debug.
  - Berkas: `info`+ selalu ditulis; `debug` hanya saat Mode Diagnostik aktif.
- **Isolate background punya berkas sendiri** (`bg-YYYYMMDD.log`). Isolate tak berbagi objek dengan app, dan dua isolate yang menulis satu berkas rawan rusak. Saat ekspor, berkas-berkas digabung.
- **Tulis ber-buffer, bukan tiap baris.** Flush tiap 2 dtk, atau segera untuk `error`. Aman baterai di hot path GPS.
- **Rotasi:** satu berkas per hari per sumber. Hapus berkas > 7 hari, dan total dibatasi 5 MB (berkas tertua dibuang dulu).
- **Event tracking terstruktur, bukan per fix.** Event: sesi start/jeda/stop/buang, engine aktif/idle, service start/stop/mati sendiri/restart, heartbeat timeout. Plus **ringkasan per menit** (titik per sesi, fix ditolak filter). Detail per fix hanya di level `debug`.
- **Keamanan:** redaksi otomatis pola rahasia (token FCM, `Authorization`, `password`, `Bearer`) sebelum ditulis. Ekspor hanya lewat tombol user.
- **Tanpa dependency baru.** Pakai `path_provider`, `archive`, `share_plus`, `permission_handler` yang sudah ada. `pubspec.yaml` tidak disentuh.
- **Hapus print:** migrasi mekanis per area.
  - `❌` → `logError`, `⚠️` → `logWarn`, sisanya → `logDebug`.
  - Kunci dengan `avoid_print: error` di `analysis_options.yaml`, plus test yang gagal bila ada `print(`/`debugPrint(` di `lib/` selain logger.

## Dependency Graph
```
T1 inti logger (format, redaksi, sink berkas, rotasi)
 └─► T2 sambung app_logger + init app & isolate + Mode Diagnostik (state)
      ├─► T3 event tracking + ringkasan per menit
      ├─► T4 UI Settings: Mode Diagnostik, Bagikan/Hapus Log ─► T5 paket ekspor (zip + info + snapshot)
      ├─► T6 breadcrumb Crashlytics
      └─► T7a–T7d migrasi print() per area ─► T7d gerbang lint + test
```

## Task List

### Phase 1 — Fondasi logger

#### Task 1: Inti logger berkas (format, redaksi, rotasi)
**Description:** Buat `AppLog` murni-Dart dengan direktori, jam, dan ukuran yang bisa disuntik.
- Format baris: `2026-09-29T08:00:01.123 I ENGINE  pesan`.
- Redaksi rahasia sebelum ditulis.
- Buffer + flush periodik; `error` di-flush segera.
- Berkas harian per sumber (`app`/`bg`); prune > 7 hari dan > 5 MB total.

**Acceptance criteria:**
- [ ] Baris ditulis ke `logs/<source>-YYYYMMDD.log` dengan format di atas; ganti hari → berkas baru.
- [ ] Token/`Authorization`/`password`/`Bearer xxx` tersamar (`***`) di berkas.
- [ ] Prune menghapus berkas tertua sampai ≤ 7 hari dan ≤ 5 MB.

**Verification:** `flutter test test/services/logging/app_log_test.dart` (temp dir, jam palsu).
**Dependencies:** None
**Files:** `lib/services/logging/app_log.dart`, `lib/services/logging/log_redactor.dart`, test
**Scope:** S–M

#### Task 2: Sambungkan logger ke app & isolate + state Mode Diagnostik
**Description:**
- `app_logger.dart` meneruskan ke `AppLog`; tambah `logInfo`/`logWarn` dan parameter `tag`. Konsol hanya di debug build.
- Init di `main()` (source `app`), pasang hook `FlutterError.onError` & zona error ke log (Crashlytics tetap).
- Init di `_onStart` isolate (source `bg`).
- Mode Diagnostik: `AppSettings.diagnosticUntil` (null = mati), dibaca kedua isolate lewat SharedPreferences, kedaluwarsa 24 jam.

**Acceptance criteria:**
- [ ] `logDebug` tertulis ke berkas hanya saat Mode Diagnostik aktif dan belum kedaluwarsa; `logInfo`+ selalu tertulis.
- [ ] Di release, tak ada output konsol dari logger.
- [ ] Error Flutter tak tertangkap ikut tercatat di berkas `app`.

**Verification:** unit test gating level × mode diagnostik × kedaluwarsa (jam palsu); `flutter analyze` 0 error.
**Dependencies:** T1
**Files:** `lib/utils/app_logger.dart`, `lib/main.dart`, `lib/services/background/background_tracking_service.dart`, `lib/models/settings/app_settings.dart`, test
**Scope:** M

### Checkpoint A
- [ ] Test hijau; install debug → berkas `app-*.log` & `bg-*.log` muncul saat tracking.

### Phase 2 — Isi log & ekspor

#### Task 3: Event tracking + ringkasan per menit
**Description:** Catat event berlevel `info` bertag:
- `SESSION`: start/jeda/lanjut/stop/buang/simpan, dengan id & sumber project.
- `ENGINE`: aktif/idle, ensureRunning ok/gagal, restart + backoff.
- `SERVICE`: start/stop/mati sendiri + alasan (heartbeat timeout, lokasi mati, error).
- `GPS`: ringkasan tiap 60 dtk per sesi — +titik, total, fix ditolak filter, akurasi median.

**Acceptance criteria:**
- [ ] Setiap transisi status sesi & engine menghasilkan satu baris `info` (bukan per fix).
- [ ] Ringkasan per menit dihitung benar dan hanya ditulis bila ada sesi merekam.
- [ ] Isolate mencatat alasan setiap `stopSelf()`.

**Verification:** unit test engine/manager dengan sink palsu; test agregator ringkasan (murni).
**Dependencies:** T2
**Files:** `lib/services/tracking/tracking_engine.dart`, `tracking_session_manager.dart`, `lib/services/tracking/tracking_log_summary.dart` (baru), `background_tracking_service.dart`, test
**Scope:** M

#### Task 4: Settings — "Log Diagnostik"
**Description:** Section baru di Settings:
- Toggle **Mode Diagnostik** (label sisa waktu, mis. "aktif 23 jam lagi").
- Info ukuran & jumlah berkas log.
- Tombol **Bagikan Log** dan **Hapus Log** (dengan konfirmasi).

**Acceptance criteria:**
- [ ] Toggle menyetel/menghapus `diagnosticUntil`; label sisa waktu benar.
- [ ] Hapus Log mengosongkan folder log (log baru tetap bisa ditulis).
- [ ] Tampilan tanpa overflow di lebar 360 dp.

**Verification:** widget test section (toggle, label, konfirmasi hapus) + test 360 dp.
**Dependencies:** T2
**Files:** `lib/screens/settings/settings_screen.dart`, `lib/widgets/settings/diagnostic_log_section.dart` (baru), test
**Scope:** M

#### Task 5: Paket ekspor "Bagikan Log"
**Description:** Flush semua buffer lalu buat `terestria-log-<device>-<waktu>.zip` berisi:
- semua `app-*.log` & `bg-*.log`;
- 3 CSV GPS terbaru;
- `info.txt`: OS & versi, model, provider GPS, versi DB, setelan GPS & cap;
- `snapshot.txt`: sesi aktif, status engine/service, izin lokasi (when-in-use/always), optimasi baterai, notifikasi.

Zip lalu dibagikan via `share_plus`.

**Acceptance criteria:**
- [ ] Zip berisi entri di atas; tak ada rahasia (redaksi berlaku).
- [ ] Snapshot memuat status tiap sesi + titik + sumber.
- [ ] Gagal buat zip → pesan jelas, app tak crash.

**Verification:** unit test builder snapshot/info (murni) + test zip di temp dir (daftar entri).
**Dependencies:** T3, T4
**Files:** `lib/services/logging/log_exporter.dart` (baru), `diagnostic_log_section.dart`, test
**Scope:** M

#### Task 6: Breadcrumb Crashlytics
**Description:**
- `warn`/`error` dari isolate app diteruskan ke `crashlytics.log`.
- `logError(..., error:, stack:)` → `recordError` non-fatal, dengan rate-limit (maks 1× per pesan per 5 menit) agar dashboard tak banjir.
- `CrashlyticsService.log` tak lagi `debugPrint`.

**Acceptance criteria:**
- [ ] `warn`/`error` muncul sebagai breadcrumb; `debug`/`info` tidak.
- [ ] Pesan error identik beruntun tak dikirim ulang dalam 5 menit.

**Verification:** unit test forwarder dengan crashlytics palsu.
**Dependencies:** T2
**Files:** `lib/utils/app_logger.dart`, `lib/services/crashlytics_service.dart`, test
**Scope:** S

### Checkpoint B
- [ ] Test hijau; di device: Mode Diagnostik ON → tracking 5 menit → Bagikan Log → zip terbuka dan berisi event + ringkasan.

### Phase 3 — Hilangkan print() (release bersih)

Aturan mekanis:
- `print('❌…')` → `logError`, `print('⚠️…')` → `logWarn`, sisanya → `logDebug`.
- Tag diisi sesuai area.
- Token/kredensial yang tercetak (mis. FCM) diganti keterangan tanpa nilai.

#### Task 7a: Migrasi print — tracking & data collection
`data_collection_screen.dart` (67), `location_provider_screen.dart`, `gps_logger_service.dart`, `notification_service.dart`, `project_card.dart`, `main.dart`.
**AC:** 0 `print(`/`debugPrint(` di file tersebut; perilaku tak berubah. **Verify:** analyze + test tracking. **Scope:** M

#### Task 7b: Migrasi print — sync, auth, cloud, notifikasi
`fcm_token_service`, `firebase_messaging_service`, `photo_sync_service`, `photo_migration_service`, `sync_service`, `auth_service`, `cloud_project_service`, `cloud_project_dialog`, `scope_topic_service`, `collector_service`, `notification_sync_service`, `migration_service`, `crashlytics_service`.
**AC:** 0 print di area ini; tak ada token/kredensial di log. **Verify:** analyze + test sync. **Scope:** M (mekanis)

#### Task 7c: Migrasi print — basemap, tile, PDF
`tile_cache_sqlite_service`, `geopdf_service`, `basemap_service`, `pdf/tile_generator`, `tile_download_manager`, `pdf/pdf_georef_extractor`, `cloud_basemap_service`, `tile_providers/*`, `cache_management_screen`.
**AC:** 0 print di area ini; loop per-tile hanya `logDebug`. **Verify:** analyze + test basemap. **Scope:** M (mekanis)

#### Task 7d: Sisa UI + gerbang anti-print
Sisa file: `photo_field_widget`, `project_detail_screen`, `geo_data_list_item`, `projects_screen`, `menu_screen`, `splash_screen`.
- Aktifkan `avoid_print: error` di `analysis_options.yaml`.
- Tambah `test/lint/no_print_test.dart` yang gagal bila ada `print(`/`debugPrint(` di `lib/` selain `lib/utils/app_logger.dart`.

**AC:** `grep` print di `lib/` = hanya logger; analyze 0 error; test gerbang hijau (dan gagal bila print ditambahkan). **Scope:** M

### Checkpoint C — Complete
- [ ] `flutter test` hijau (kecuali 2 kegagalan lama: photoWatermark, OSM sheet parity); `flutter analyze` 0 error.
- [ ] Build release: logcat tak berisi spam print app; log tetap tercatat di berkas & bisa dibagikan.

## Risks and Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Tulis berkas di hot path GPS menguras baterai | Med | Buffer + flush 2 dtk; per-fix hanya level debug (Mode Diagnostik) |
| Berkas log membengkak | Med | Rotasi harian + batas 7 hari / 5 MB |
| Token/kredensial bocor ke berkas yang dibagikan | High | Redaktor pola rahasia di sink + migrasi FCM tanpa nilai token + test redaksi |
| Dua isolate menulis bersamaan | Med | Berkas terpisah per isolate (`app`/`bg`) |
| Migrasi 370 print mengubah perilaku | Low | Mekanis (hanya ganti fungsi log), analyze + test per area, commit per area |
| path_provider di isolate background | Low | `DartPluginRegistrant.ensureInitialized()` sudah dipanggil; fallback: log isolate diam bila gagal init |

## Keputusan (default bila tak ada jawaban lain)
1. **Koordinat di log: lengkap** (paling berguna untuk debug GPS); ekspor hanya lewat tombol user. Bisa diubah ke pembulatan 4 desimal.
2. **Mode Diagnostik** mati otomatis setelah **24 jam**.
3. **Retensi** 7 hari / 5 MB.
4. Build release tetap mencatat `info`+ ke berkas (tanpa konsol).
