# TODO — Fix Sync Foto Parsial

Branch: `fix/partial-photo-sync` · Plan: [plan.md](plan.md)

## Fase 0 — Fondasi
- [x] 0.1 `pendingPhotoUploads(formData, project)` di PhotoSyncService + DI ringan di SyncService
  - AC: 1 foto null-serverKey di antara 2 yang ok → return 1; `http` diabaikan; file hilang → `fileExists=false` ✅
  - Verify: `flutter test test/services/photo_sync_service_test.dart` ✅ (5 test hijau)

## Fase 1 — Hentikan kerusakan baru
- [x] 1.1 Guard di `syncGeoData`: simpan progres parsial, blokir `isSynced=true` bila ada foto pending, laporkan Crashlytics ✅
  - AC: 1 foto gagal → record tetap `unsynced`, serverKey sukses tersimpan, `success=false`; tak ada jalur synced dgn serverKey null ✅
  - Verify: unit test fake upload (1 null) ✅ (2 test hijau)
- [x] **CP-A**: review guard (kebijakan foto file-hilang: ✅ tetap unsynced + ditandai — plan §3)

## Fase 2 — Ketahanan upload
- [x] 2.1 Timeout + `crashlytics.recordError` di `ApiService.uploadFile` ✅
  - AC: upload menggantung berhenti oleh timeout; kegagalan tercatat dgn konteks ✅
  - Verify: simulasi upload lambat/gagal ✅ (3 test hijau via MockClient)

## Fase 3 — Pemulihan data lama
- [x] 3.1 `recoverIncompletePhotoSyncs()` di MigrationService (guard flag, idempotent), reset record rusak → unsynced ✅
  - AC: record 2 ok + 1 null(file ada) → `isSynced=false`; run kedua no-op ✅
  - Verify: seed via fake StorageService → jalankan → assert; jalankan lagi → no-op ✅ (2 test hijau)
  - Catatan: tambah `getSyncedGeoData()` di StorageService + DatabaseService (mirror `getUnsyncedGeoData`)
- [ ] **CP-B**: review ringkasan `{scanned, resetForRetry, unrecoverable}` di data nyata (manual, saat run di device)
- [x] 3.2 Panggil recovery di `app_initializer.dart` setelah `migrate()` (non-blocking) ✅
  - Flag hanya diset bila scan sukses → error transien tidak melewatkan recovery (test hijau)
  - Verify: `flutter analyze` bersih + test resiliensi; app-on-device manual (CP-B)

## Fase 4 — Regression
- [x] 4.1 Test suite: sukses penuh / parsial / recovery idempotent ✅
  - Ditambah integration test (real `processFormDataForPush` + guard, hanya POST & storage difake)
  - Verify: `flutter test` hijau → **20/20 test**
- [x] **CP-C**: `flutter test` hijau (20/20); `flutter analyze` tidak menambah isu baru dari perubahan ini (sisa 813 isu pre-existing repo-wide, di luar scope) → siap PR

---

# Fase Lanjutan — Hasil Review (plan §9-12)

## Fase 5 — Konsistensi & Hardening
- [x] 5.1 (IMPORTANT) Samakan predikat upload push ke `serverKey` via helper `needsUpload` + test ✅
  - AC: foto ber-`serverKey` tak pernah re-upload (walau serverUrl null/stale); `serverKey==null` → dicoba; guard & push sepakat pada `serverKey` ✅
  - Verify: unit test helper (4 kasus); `flutter test` hijau → 24/24
- [x] **CP-D**: guard (`pendingPhotoUploads`) & push (`needsUpload`) kini sama-sama key ke `serverKey` → tak ada deadlock; test hijau ✅
- [x] 5.2 (SUGGESTION) Logging hygiene: jangan log signed URL ✅
  - Ganti 2 log upload sukses → `key=...`; download error → strip query (buang signature)
  - AC: tak ada `print` memuat signed URL penuh; log tetap informatif (serverKey/nama) ✅
  - Verify: grep bersih (sisa `$response` hanya di jalur gagal, tanpa signed URL); `flutter test` 24/24; analyze tak menambah isu
  - Catatan: perubahan logging murni → verifikasi lewat grep+regresi (tak ada seam unit-test yang bersih)
- [x] 5.3 (IMPORTANT) Laporkan record `unrecoverable` (ID) ke Crashlytics + `unrecoverableIds` di result ✅
  - AC: result memuat daftar ID; dilaporkan ke Crashlytics; `unrecoverable` = `unrecoverableIds.length` ✅
  - Verify: `migration_recovery_test` → `unrecoverableIds` memuat `rec3`, bukan `rec1`; `flutter test` 24/24
- [x] **CP-E**: awalnya ditunda, lalu diminta dikerjakan ✅
- [x] 5.4 (SUGGESTION) Paralelisasi upload per-record dgn konkurensi terbatas (`maxConcurrentUploads=3`) ✅
  - AC: N foto ter-proses; urutan dipertahankan; partial-failure tetap → serverKey null (tertangkap guard) ✅
  - Verify: test konkurensi (parallel >1, ≤3) + partial-failure + no re-upload; `flutter test` 26/26
- [x] **CP-F**: `flutter test` hijau (26/26) + `flutter analyze` tak menambah isu ✅

---

# Fase 6 — Optimasi performTwoWaySync (delta sync) — plan §13-18

Keputusan: backend BISA tambah `updated_after` → **delta sync berbasis watermark**.

- [x] 6.1 `SyncWatermarkService` (get/set/clear last-pull per project, UTC, SharedPreferences) ✅
  - AC: set→get instant sama (UTC); kosong→null; clear hapus; terpisah per project ✅
  - Verify: unit test `setMockInitialValues` → 5 test hijau (total 31/31)
- [x] 6.2 (IMPORTANT) Delta pull di `pullGeoDataFromServer` (kirim `updated_after`, majukan watermark hanya saat sukses penuh) ✅
  - AC: URL memuat `updated_after` bila watermark ada; watermark maju setelah sukses; page error → tak maju; server abaikan param → tetap jalan ✅
  - Verify: unit test `SyncService.forTest` + fake ApiService.get/Storage/PhotoSync + watermark real (mock prefs) → 3 test hijau (34/34)
- [x] **CP-G**: backward-compat aman (param aditif; klien tak bergantung server menghormatinya — per-record skip tetap jalan) + korektnes watermark (maju hanya saat sukses penuh, tak mundur) ✅
- [x] 6.3 Opsi `forceFull` (pull-to-refresh manual abaikan watermark) ✅
  - AC: `forceFull:true` → tak kirim `updated_after`; tetap tulis watermark baru ✅
  - Verify: unit test forceFull → URL tanpa param, watermark maju → 35/35 hijau
  - Catatan: mekanisme + wiring UI selesai — pull-to-refresh di project_detail_screen kini `forceFull:true`; tombol sync tetap delta
- [~] 6.4 (NON-KODING) Kontrak API ditulis → `docs/sync-delta-api-contract.md` ✅; **menunggu deploy server** oleh tim backend
- [ ] **CP-H**: pastikan backend `updated_after` deploy sebelum aktif di PROD (klien aman rilis dulu — degradasi aman)

> Deletion tak tertangani (perlu tombstone) — di luar scope, sama seperti sekarang.

> Out of scope repo ini: validasi backend menolak payload `serverKey: null` — koordinasikan dgn tim server.

---

# Fase 7 — Aktifkan R8 (minify + shrinkResources) Build Release Android — plan §19-24

Status: **DRAFT — menunggu review**. Catatan: build & uji APK release dijalankan **user** (CLI tak ada di sandbox agent).

## Phase 1 — Fondasi
- [x] 7.1 Buat `android/app/proguard-rules.pro` dengan keep rules lengkap (GraphHopper/JTS/hppc, ML Kit, local_notifications, Play Core, Firebase, geolocator/permission/background) ✅
  - AC: file dibuat; semua dependency berisiko native/refleksi tercakup keep/dontwarn ✅
- [x] 7.2 `build.gradle` release: `minifyEnabled true` + `proguardFiles ...optimize.txt, proguard-rules.pro` (shrinkResources tetap false) ✅ (edit selesai)
  - AC: minify + proguardFiles aktif; shrinkResources false ✅
  - Verify (USER): `flutter run --release` → **build sukses (app-release.apk 48.5MB), tanpa Missing class, app launch ke home** ✅
  - Catatan: perlu bump `google-services` 4.4.0 → 4.4.2 (settings.gradle + build.gradle classpath) karena Crashlytics plugin v3 mensyaratkan 4.4.1+ saat minify aktif.
- [x] **CP-I** ✅: build release sukses tanpa `Missing class`; app buka sampai home (Firebase/FCM/migration/recovery OK)

## Phase 2 — Uji fungsional & resource shrinking
- [~] 7.3 Smoke-test subsistem berisiko di APK release (minify) — ⏳ SEDANG DIUJI USER
  - Startup/init: Firebase, Crashlytics, FCM token, migration, recovery, navigasi ✅ (dari log launch)
  - ✅ Terverifikasi di release (no crash R8): login+sync (fetch 51 project, pull geodata), FCM token+subscribe, GPS foreground+background isolate+notif service, basemap+tile cache SQLite, permission flow
  - ⏳ Belum diuji (paling rawan R8, belum disentuh): [ ] routing GraphHopper (Navigation)  [ ] QR scanner (mobile_scanner/ML Kit)  [ ] render PDF basemap
  - Warning non-R8 (pre-existing, aman): flutter_background_service "main isolate" warning; listener retry #1/5 — tracking tetap jalan
  - AC: semua subsistem jalan di APK release; tiap crash → kirim stacktrace → keep rule ditambah → rebuild
  - Catatan APK size (minify, shrinkResources off): 48.5MB
- [~] 7.4 `shrinkResources true` + `res/raw/keep.xml` — ⏳ menunggu rebuild user
  - Iterasi 1: keep hanya `ic_stat_edit_location` → FCM error `invalid_icon: @drawable/ic_stat_notification could not be found` (ikut ke-strip)
  - Iterasi 2 (fix): keep pakai wildcard `@drawable/ic_stat_*` → menahan ic_stat_edit_location & ic_stat_notification (dirujuk via string Dart di firebase_messaging_service.dart:139)
  - AC: shrinkResources aktif; kedua ikon notifikasi tetap ada; ikon notif tampil (tracking/FCM) ✅
  - Verify (user): `flutter run --release` → **FCM init bersih, no invalid_icon** ✅; APK 48.4MB (dari 48.5MB, turun tipis — wajar utk Flutter, dominan .so 4-ABI)
- [x] **CP-J** ✅: shrinkResources aktif, ikon notifikasi selamat, app launch bersih
  - Catatan ukuran: penghematan besar butuh split per-ABI (AAB Play Store / `--split-per-abi`) — dibahas di 7.6

## Phase 3 — Verifikasi & rilis
- [x] 7.5 Mapping Crashlytics — task `uploadCrashlyticsMappingFileRelease` jalan saat build sukses ✅ (opsional: uji crash sintetis konfirmasi deobfuscate)
  - Ukuran: minify only 48.5MB → +shrinkResources 48.4MB (dominan .so 4-ABI; hemat besar via AAB split)

### Keputusan rilis (dari user)
- Format: **AAB (Play Store)** → uji via bundletool/internal track
- Obfuscation Dart: **YA** (`--obfuscate --split-debug-info`)

- [~] 7.6 Regresi penuh + siap rilis (AAB + obfuscate) — ⏳ USER
  - Setup selesai: `build.sh` → AAB + obfuscate, symbols → `release_symbols/<versi>/`; `.gitignore` diperbaiki agar symbols rilis tetap tersimpan
  - [ ] Jalankan `./build.sh` → AAB build sukses
  - [ ] Uji AAB via bundletool `--local-testing` (atau internal testing track Play)
  - [ ] Regresi penuh alur utama di build obfuscated: project, data collection, layers, basemap/PDF, **navigation (GraphHopper)**, notifications/FCM, sync, settings, **QR scanner**
  - [ ] Simpan `release_symbols/<versi>/` (commit atau arsip aman) — wajib utk symbolicate crash Dart
- [ ] **CP-K**: semua alur lulus di AAB obfuscated; symbols tersimpan; siap upload Play Store

### Catatan penting
- **R8 mapping.txt** → otomatis ke Crashlytics (Android/Java crash terbaca).
- **Symbols Dart** → TIDAK auto-upload; baca crash Dart manual: `flutter symbolize -i <trace> -d release_symbols/<versi>/app.android-arm64.symbols`.
- Belum diuji sejak awal (WAJIB di regresi 7.6): routing GraphHopper, QR scanner, PDF basemap render.
