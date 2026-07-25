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
- [ ] **CP-B**: review ringkasan `{scanned, resetForRetry, unrecoverable}` di data nyata
- [ ] 3.2 Panggil recovery di `app_initializer.dart` setelah `migrate()` (non-blocking)
  - Verify: app dengan data rusak → record jadi unsynced

## Fase 4 — Regression
- [ ] 4.1 Test suite: sukses penuh / parsial / recovery idempotent
  - Verify: `flutter test` hijau
- [ ] **CP-C**: `flutter test` + `flutter analyze` hijau → buka PR
