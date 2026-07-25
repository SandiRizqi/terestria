# Rencana Perbaikan: Sync Foto Parsial (serverKey null tapi isSynced true)

Status: **DRAFT — menunggu review**
Tanggal: 2026-07-25
Branch usulan: `fix/partial-photo-sync`

---

## 1. Konteks & Akar Masalah

Ditemukan record dengan `isSynced: true` tetapi salah satu foto memiliki
`serverKey: null` / `serverUrl: null`. Ini **bukan** sekadar status UI salah —
foto tersebut tidak pernah naik ke OSS dan **tidak akan pernah di-retry**,
karena record sudah dianggap tersinkron. Risiko: kehilangan data foto permanen.

Rantai penyebab (sudah diverifikasi di kode):

1. `ApiService.uploadFile` menelan semua error → `return null`, tanpa timeout
   ([api_service.dart:239-286](../lib/services/api_service.dart#L239)).
2. `PhotoSyncService.uploadSinglePhoto` → `null` bila file tak ada / response
   gagal ([photo_sync_service.dart:78-105](../lib/services/photo_sync_service.dart#L78)).
3. `processFormDataForPush`: bila upload `null`, metadata **tetap ditambahkan**
   dengan `serverKey/serverUrl == null`, tanpa error
   ([photo_sync_service.dart:226-239](../lib/services/photo_sync_service.dart#L226)).
4. `syncGeoData` menandai `isSynced: true` setelah POST `200`, **tanpa memeriksa
   kelengkapan foto** ([sync_service.dart:62-71](../lib/services/sync_service.dart#L62)).
5. Record synced tidak pernah masuk `getUnsyncedGeoData()` lagi → foto yatim.

Kenapa biasanya foto pertama: `updated == created` pada foto gagal menandakan
`uploadSinglePhoto` mengembalikan `null` sebelum menyentuh jaringan — file lokal
kemungkinan sudah tidak ada saat sync (`file.existsSync() == false`).

---

## 2. Scope

**In scope**
- Guard: jangan set `isSynced = true` selama masih ada foto tanpa `serverKey`.
- Persist progres parsial: foto yang **berhasil** upload harus tersimpan
  `serverKey`-nya agar tidak di-upload ulang saat retry.
- Ketahanan upload: timeout + laporkan kegagalan ke Crashlytics (bukan `print`).
- Pemulihan data lama: reset record `isSynced=true` yang fotonya belum lengkap
  menjadi `unsynced` agar di-retry (selama file lokal masih ada).
- Unit test untuk skenario upload parsial & pemulihan.

**Out of scope (sesuai arahan)**
- `serverUrl` kedaluwarsa — **tidak diubah**, karena selalu diperbarui saat fetch
  data dari server.
- Optimasi `performTwoWaySync` yang menarik semua geodata tiap kali (isu performa,
  bukan integritas) — dicatat, tidak dikerjakan di sini.
- Pembersihan dead code (`_parseGeoDataFromServer`) & migrasi `print → app_logger`
  global — opsional, tidak menghalangi perbaikan.

---

## 3. Keputusan (SUDAH DIPUTUSKAN — 2026-07-25)

**Kebijakan untuk foto yang file lokalnya sudah hilang & belum punya serverKey**
(benar-benar tidak bisa dipulihkan):

> ✅ **Opsi 1 dipilih:** record tetap `unsynced` + ditandai/dilaporkan ke user,
> supaya tidak ada data "seolah lengkap" padahal foto hilang. Konsekuensi: record
> itu akan terus muncul sebagai "belum sync" sampai ditangani manual.

Implikasi implementasi:
- **Task 1.1:** foto pending (baik file ada maupun hilang) → record tetap
  `isSynced=false`, tidak pernah ditandai synced diam-diam.
- **Task 3.1:** record rusak dengan file hilang tetap dihitung `unrecoverable`
  namun **juga di-reset jadi `unsynced`** agar tampak "belum sync" di UI, bukan
  dibiarkan sebagai synced palsu. Ringkasan tetap memisah `resetForRetry`
  (file ada, bisa sukses) vs `unrecoverable` (file hilang, akan gagal terus)
  untuk pelaporan.

---

## 4. Dependency Graph

```
Task 0.1 (helper deteksi foto belum lengkap + DI ringan)
   ├── Task 1.1 (guard di syncGeoData)  ──┐
   │        └── Task 2.1 (timeout+Crashlytics upload)  (bisa paralel)
   └── Task 3.1 (recovery migration) ── Task 3.2 (wiring startup)
                                               │
Task 4.1 (regression tests) ← butuh 1.1 & 3.1
```

Urutan eksekusi: **0.1 → 1.1 → 2.1 → 3.1 → 3.2 → 4.1**
(2.1 boleh disisipkan kapan saja setelah 0.1).

---

## 5. Tugas (Vertical Slices)

### Fase 0 — Fondasi

**Task 0.1 — Helper deteksi foto belum ter-upload + DI ringan**
- Tambah `PhotoSyncService.pendingPhotoUploads(formData, project)` yang
  mengembalikan `List<PendingPhoto>` (field label, name, localPath, `fileExists`).
  "Pending" = item foto dengan `serverKey == null` dan `localPath` bukan `http`.
- Refactor kecil: buat `SyncService` menerima injeksi opsional
  (`ApiService`/`PhotoSyncService`/`StorageService`) via constructor, default ke
  singleton — supaya bisa di-unit-test.
- **Acceptance:**
  - formData dengan 1 foto `serverKey==null` + 2 foto ber-`serverKey` → hasil 1.
  - Foto dengan `localPath` diawali `http` diabaikan.
  - Foto pending yang filenya tidak ada → `fileExists == false`.
  - Fungsi murni (tanpa network/DB), bisa dites langsung.
- **Verify:** `flutter test test/services/photo_sync_service_test.dart`.

### Fase 1 — Hentikan kerusakan baru

**Task 1.1 — Guard kelengkapan foto sebelum menandai synced**
- Di `syncGeoData` ([sync_service.dart:57-71](../lib/services/sync_service.dart#L57)):
  1. Setelah `processFormDataForPush`, **simpan progres parsial** ke lokal
     (`copyWith(formData: processed, isSynced: false)`) supaya `serverKey` foto
     yang sudah berhasil tidak hilang / tidak di-upload ulang.
  2. Panggil `pendingPhotoUploads(processed, project)`. Jika tidak kosong:
     - Jangan kirim POST final / jangan set `isSynced=true`.
     - `crashlytics.recordError` dengan konteks (id, jumlah & nama foto gagal).
     - Return `SyncResult(success:false, message:'N foto gagal di-upload, akan dicoba lagi')`.
  3. Jika kosong → lanjut POST → set `isSynced=true` seperti biasa.
- **Acceptance:**
  - Bila 1 dari N foto gagal upload → record tetap `isSynced=false`, `serverKey`
    foto yang sukses tersimpan lokal, pesan jelas ke pemanggil.
  - **Tidak ada** jalur yang menghasilkan `isSynced=true` sementara ada foto
    `serverKey==null`.
- **Verify:** unit test dengan fake `PhotoSyncService`/`ApiService` (1 upload
  `null`) → assert record unsynced + `success==false`.

### Fase 2 — Ketahanan upload

**Task 2.1 — Timeout + pelaporan kegagalan upload**
- `ApiService.uploadFile`: bungkus `request.send()` dengan `.timeout(...)`
  (pakai `ApiConfig` timeout), laporkan non-2xx & exception via
  `crashlytics.recordError` (konteks: filename, statusCode) alih-alih `print`.
- Opsional: satu kali retry untuk kegagalan transien.
- **Acceptance:** upload yang menggantung berhenti oleh timeout; kegagalan
  tercatat di Crashlytics dengan konteks.
- **Verify:** simulasi upload lambat/gagal (unit atau manual), cek log/Crashlytics.

### Fase 3 — Pemulihan data lama

**Task 3.1 — Recovery pass sekali jalan**
- Tambah metode di `MigrationService` (mis. `recoverIncompletePhotoSyncs()`),
  di-guard flag baru (mis. `has_recovered_partial_photo_sync_v1`).
- Scan semua record `isSynced=true`; untuk tiap record ambil project-nya, jalankan
  `pendingPhotoUploads`:
  - Ada pending & file lokal **ada** → `updateGeoDataSyncStatus(id, false)` agar
    di-retry sync normal.
  - Ada pending tapi file lokal **hilang** → hitung sebagai `unrecoverable`,
    tangani sesuai keputusan Checkpoint A.
- Kembalikan ringkasan `{scanned, resetForRetry, unrecoverable}`.
- **Acceptance:**
  - Record 2 foto ok + 1 foto `serverKey==null` (file ada) → jadi `isSynced=false`.
  - Idempotent: dijalankan dua kali, run kedua no-op.
- **Verify:** seed DB record rusak → jalankan → assert `isSynced=false`; jalankan
  lagi → tidak ada perubahan.

**Task 3.2 — Wiring recovery ke startup**
- Panggil `recoverIncompletePhotoSyncs()` di
  [app_initializer.dart](../lib/app_initializer.dart) **setelah** `migrate()`.
- Log ringkasan (opsional snackbar/log). Tidak memblokir startup bila gagal.
- **Acceptance:** saat app pertama kali dibuka setelah update, record rusak
  otomatis dijadwalkan retry; startup tetap jalan walau recovery error.
- **Verify:** jalankan app di device dengan data rusak → cek record jadi unsynced.

### Fase 4 — Regression tests

**Task 4.1 — Test suite sync foto**
- Kasus: (a) semua foto sukses → synced; (b) upload parsial → tetap unsynced +
  serverKey sukses tersimpan; (c) recovery mengubah record rusak jadi unsynced &
  idempotent.
- **Verify:** `flutter test` hijau; `flutter analyze` bersih.

---

## 6. Checkpoints

- **CP-A (setelah Fase 1):** review guard + putuskan kebijakan foto file-hilang
  (lihat §3) sebelum lanjut ke recovery.
- **CP-B (setelah Task 3.1, sebelum 3.2):** review ringkasan recovery pada salinan
  data nyata; putuskan rollout ke startup.
- **CP-C (setelah Fase 4):** `flutter test` + `flutter analyze` hijau sebelum
  buka PR.

---

## 7. Risiko & Mitigasi

- **Retry storm** setelah recovery (banyak record jadi unsynced sekaligus):
  sync normal sudah early-abort saat koneksi putus; upload foto sukses tak diulang
  karena progres parsial tersimpan (Task 1.1).
- **Foto file hilang → retry selamanya:** ditangani oleh keputusan Checkpoint A.
- **Belum ada mocking framework** (hanya `flutter_test`): ditangani lewat DI ringan
  di Task 0.1 (fake sederhana, tanpa menambah dependency).
- **Perubahan menyentuh jalur kritikal (sync):** kerjakan di branch terpisah,
  merge hanya setelah CP-C.

---

## 8. Berkas yang Akan Disentuh

- `lib/services/photo_sync_service.dart` (helper, timeout terkait)
- `lib/services/api_service.dart` (timeout + Crashlytics upload)
- `lib/services/sync_service.dart` (guard + DI)
- `lib/services/migration_service.dart` (recovery pass)
- `lib/app_initializer.dart` (wiring)
- `test/services/…` (unit test baru)
