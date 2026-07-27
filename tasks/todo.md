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

- [ ] 6.1 `SyncWatermarkService` (get/set/clear last-pull per project, UTC, SharedPreferences)
  - AC: set→get instant sama (UTC); kosong→null; clear hapus
  - Verify: unit test `setMockInitialValues`
- [ ] 6.2 (IMPORTANT) Delta pull di `pullGeoDataFromServer` (kirim `updated_after`, majukan watermark hanya saat sukses penuh)
  - AC: URL memuat `updated_after` bila watermark ada; watermark maju setelah sukses; page error → tak maju; server abaikan param → tetap jalan
  - Verify: unit test `SyncService.forTest` + fake ApiService.get/Storage/PhotoSync/watermark
- [ ] **CP-G**: verifikasi backward-compat + korektnes watermark
- [ ] 6.3 Opsi `forceFull` (pull-to-refresh manual abaikan watermark)
  - AC: `forceFull:true` → tak kirim `updated_after`; tetap tulis watermark baru
  - Verify: unit test forceFull → URL tanpa param
- [ ] 6.4 (NON-KODING) Koordinasi backend: deploy `updated_after` inklusif & backward-compat (kontrak plan §14)
- [ ] **CP-H**: pastikan backend `updated_after` deploy sebelum aktif di PROD (klien aman rilis dulu — degradasi aman)

> Deletion tak tertangani (perlu tombstone) — di luar scope, sama seperti sekarang.

> Out of scope repo ini: validasi backend menolak payload `serverKey: null` — koordinasikan dgn tim server.
