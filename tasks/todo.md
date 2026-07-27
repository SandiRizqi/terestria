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
- [ ] 5.2 (SUGGESTION) Logging hygiene: jangan log signed URL (push :307/:336, cek `downloadPhoto`)
  - AC: tak ada `print` memuat `file_url`/`serverUrl` penuh; log tetap informatif (serverKey/nama)
  - Verify: grep bersih; `flutter analyze` tak menambah isu; test hijau
- [ ] 5.3 (IMPORTANT) Laporkan record `unrecoverable` (ID) ke Crashlytics + `unrecoverableIds` di result
  - AC: result memuat daftar ID; dilaporkan ke Crashlytics; hitungan konsisten
  - Verify: perluas `migration_recovery_test` → `unrecoverableIds` memuat `rec3`
- [ ] **CP-E**: keputusan — kerjakan 5.4 sekarang atau tunda (rate-limit & error handling)
- [ ] 5.4 (SUGGESTION, opsional) Paralelisasi upload per-record dgn konkurensi terbatas
  - AC: N foto ter-proses; partial-failure tetap → record unsynced
  - Verify: test partial-failure lulus; cek perf manual
- [ ] **CP-F**: `flutter test` hijau + `flutter analyze` tak menambah isu

> Out of scope repo ini: validasi backend menolak payload `serverKey: null` — koordinasikan dgn tim server.
