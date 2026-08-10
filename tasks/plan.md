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

---

# Rencana Lanjutan — Hasil Review (Fase 5)

Status: **DRAFT — menunggu review**
Tanggal: 2026-07-27
Konteks: temuan dari review alur upload/pull foto setelah Fase 0–4 selesai.

## 9. Temuan yang Ditangani

1. **(IMPORTANT)** Predikat "sudah ter-upload?" tidak konsisten: push memakai
   `serverUrl == null` ([photo_sync_service.dart:297](../lib/services/photo_sync_service.dart#L297),
   [:326](../lib/services/photo_sync_service.dart#L326)) sedangkan guard memakai
   `serverKey == null`. Rapuh → potensi deadlock (guard blokir, push menolak
   re-upload) bila kedua field tak sinkron. `serverKey` = source-of-truth
   (serverUrl signed & diregenerasi server saat fetch).
2. **(IMPORTANT)** Recovery hanya menyelamatkan foto di device sumber; record
   dengan file lokal hilang = hilang permanen. Saat ini `unrecoverable` hanya
   dihitung, ID-nya tidak dilaporkan → tak bisa dilacak.
3. **(SUGGESTION)** Signed OSS URL (mengandung `Signature`) ikut ter-`print`
   ([:307](../lib/services/photo_sync_service.dart#L307),
   [:336](../lib/services/photo_sync_service.dart#L336)).
4. **(SUGGESTION, opsional)** Upload/pull foto per-record masih serial;
   `uploadMultiplePhotos`/`downloadMultiplePhotos` paralel ada tapi tak dipakai.

Out of scope repo ini: validasi sisi server agar menolak payload `serverKey:
null` (backend terpisah) — dicatat untuk dikoordinasikan, bukan task di sini.

## 10. Dependency Graph

```
Task 5.1 (align predikat → serverKey) ── Task 5.2 (logging hygiene, file sama)
Task 5.3 (laporkan unrecoverable IDs)  [independen]
Task 5.4 (paralelisasi upload, opsional) ── butuh 5.1 lebih dulu
```
Urutan: **5.1 → 5.2 → 5.3 → (5.4 opsional)**.

## 11. Tugas

### Task 5.1 — Samakan predikat upload ke `serverKey` (IMPORTANT)
- Tambah helper murni `_needsUpload(PhotoMetadata m)` =
  `m.serverKey == null && !m.localPath.startsWith('http')`.
- Pakai helper di kedua call-site push (baris ~297 & ~326) menggantikan cek
  `serverUrl == null`.
- **Acceptance:**
  - Foto dengan `serverKey` terisi TIDAK pernah di-upload ulang (walau
    `serverUrl` null/stale).
  - Foto dengan `serverKey == null` (localPath non-http) → dicoba upload.
  - Guard (`pendingPhotoUploads`) & push kini sepakat pada `serverKey`.
- **Verify:** unit test helper (serverKey null→true; terisi→false; localPath
  http→false). `flutter test` hijau.

### Task 5.2 — Logging hygiene: jangan log signed URL (SUGGESTION)
- Ganti log yang mencetak `file_url`/`serverUrl`/`ossUrl` penuh menjadi
  `serverKey`/nama file saja (push :307 & :336; cek juga `downloadPhoto`).
- **Acceptance:** tidak ada jalur yang mencetak URL bertanda tangan; log tetap
  informatif (nama/serverKey).
- **Verify:** grep tak menemukan `print` yang memuat `file_url`/`serverUrl`;
  `flutter analyze` tak menambah isu; tests hijau.

### Task 5.3 — Laporkan record unrecoverable (IMPORTANT)
- `recoverIncompletePhotoSyncs` kumpulkan ID record `unrecoverable` (semua foto
  pending file-nya hilang) dan laporkan ke Crashlytics (non-fatal) dengan
  konteks. Tambah `unrecoverableIds` di `PhotoSyncRecoveryResult`.
- **Acceptance:** hasil recovery memuat daftar ID unrecoverable; ID dilaporkan
  ke Crashlytics; hitungan `unrecoverable` tetap konsisten dengan panjang list.
- **Verify:** perluas `migration_recovery_test` → assert `unrecoverableIds`
  memuat `rec3`. `flutter test` hijau.

### Task 5.4 — Paralelisasi upload per-record (SUGGESTION, OPSIONAL)
- Upload foto dalam satu record dengan konkurensi terbatas (mis. 3) alih-alih
  serial; pemetaan hasil & urutan tetap benar; kegagalan sebagian tetap membuat
  `serverKey` null → tertangkap guard.
- **Acceptance:** N foto ter-proses; perilaku partial-failure tak berubah
  (record tetap unsynced bila ada yang gagal).
- **Verify:** unit test partial-failure tetap lulus; cek perf manual.
- **Risiko:** rate-limit OSS, agregasi error → butuh keputusan di CP-E.

## 12. Checkpoints Lanjutan

- **CP-D (setelah 5.1):** pastikan tak ada deadlock guard↔push; test hijau.
- **CP-E (sebelum 5.4):** putuskan apakah paralelisasi dikerjakan sekarang atau
  ditunda (pertimbangkan rate-limit & penanganan error).
- **CP-F (akhir):** `flutter test` hijau + `flutter analyze` tak menambah isu.

---

# Rencana Lanjutan — Optimasi `performTwoWaySync` (Fase 6)

Status: **DRAFT — menunggu review**
Tanggal: 2026-07-27
Keputusan kunci: **backend BISA menambah filter `updated_after`** → pendekatan
**delta sync berbasis watermark per-project**.

## 13. Masalah & Pendekatan

`performTwoWaySync` ([sync_service.dart:594](../lib/services/sync_service.dart#L594))
menarik **semua** geodata **semua project** tiap kali (semua halaman), lalu
skip per-record berdasarkan `updatedAt`. Boros network/parse walau tak ada
perubahan.

**Pendekatan:** klien menyimpan watermark per-project (timestamp `updatedAt`
tertinggi yang berhasil ditarik). Saat pull, kirim `updated_after=<watermark>`
sehingga server hanya balas record yang berubah. Watermark **hanya dimajukan
setelah pull satu project sukses penuh** (semua halaman) agar tak ada record
terlewat. Sync pertama (watermark null) = full pull.

**Degradasi aman:** bila server mengabaikan param, klien tetap berfungsi (full
pull seperti sekarang) — jadi klien boleh rilis lebih dulu.

## 14. Kontrak `updated_after` (untuk tim server)

- Query param `updated_after=<ISO8601 UTC>` pada `…/geodata/by-project/`.
- Filter **inklusif** (`updated_at >= updated_after`) untuk menghindari record
  di batas granularitas jam terlewat; klien sudah dedup via skip `updatedAt`.
- Field acuan = `updated_at`; hasil diurutkan `updated_at` menaik lebih baik.
- Tanpa param → perilaku lama (kembalikan semua). Backward-compatible.
- **Deletion tidak tercakup** (butuh tombstone) — di luar scope, sama seperti
  perilaku full-pull sekarang.

## 15. Dependency Graph

```
Task 6.1 (SyncWatermarkService) ── Task 6.2 (delta pull pakai watermark)
                                        └── Task 6.3 (opsi force full refresh)
Task 6.4 (koordinasi backend `updated_after`) — prasyarat PROD, paralel
```
Urutan koding: **6.1 → 6.2 → 6.3**. 6.4 non-koding, jalan paralel.

## 16. Tugas

### Task 6.1 — `SyncWatermarkService` (fondasi)
- Service tipis di atas SharedPreferences: `getLastPull(projectId)` →
  `DateTime?` (UTC), `setLastPull(projectId, DateTime)`, `clear(projectId)`.
  Key: `last_pull_<projectId>`, simpan ISO8601 UTC.
- **Acceptance:** set→get mengembalikan instant sama (UTC); belum ada → null;
  clear menghapus.
- **Verify:** unit test dgn `SharedPreferences.setMockInitialValues`.

### Task 6.2 — Delta pull di `pullGeoDataFromServer` (IMPORTANT)
- Inject `SyncWatermarkService` ke `SyncService` (via `forTest`).
- Di awal pull, baca watermark; bila ada, tambahkan `&updated_after=<iso>` ke
  URL request. Lacak `maxUpdatedAt` lintas semua halaman.
- **Hanya** setelah loop paginasi selesai tanpa error, tulis watermark =
  `max(maxUpdatedAt, watermarkLama)`. Bila ada page gagal → return gagal, **tak
  memajukan** watermark.
- Watermark null → tak kirim param (full pull).
- **Acceptance:**
  - Watermark ada → URL memuat `updated_after=<watermark>`.
  - Pull sukses penuh → watermark maju ke `updatedAt` tertinggi record.
  - Page error → watermark tak berubah.
  - Backward-compat: server abaikan param → tetap jalan.
- **Verify:** unit test `SyncService.forTest` dgn fake `ApiService.get`
  (canned JSON multi-page, tangkap URL), fake `StorageService`, fake
  `PhotoSyncService.processFormDataForPull` (tanpa download), fake watermark.

### Task 6.3 — Opsi "force full refresh"
- `pullGeoDataFromServer(projectId, {bool forceFull = false})`: bila true,
  abaikan watermark (full pull) — untuk pull-to-refresh manual / pemulihan bila
  data terasa desync. Wire ke pemicu refresh manual di UI.
- **Acceptance:** `forceFull:true` tidak mengirim `updated_after` walau watermark
  ada; tetap menulis watermark baru setelah sukses.
- **Verify:** unit test forceFull → URL tanpa `updated_after`.

### Task 6.4 — Koordinasi backend (NON-KODING, prasyarat PROD)
- Sampaikan kontrak §14 ke tim server; konfirmasi deploy `updated_after`.
- **Acceptance:** endpoint mendukung `updated_after` inklusif & backward-compat.
- **Verify:** uji manual: request dgn `updated_after` mengembalikan subset benar.

## 17. Checkpoints Lanjutan

- **CP-G (setelah 6.2):** verifikasi backward-compat (server abaikan param tetap
  jalan) + korektnes watermark (maju hanya saat sukses penuh).
- **CP-H (sebelum aktif di PROD):** pastikan backend `updated_after` sudah
  deploy (Task 6.4). Klien aman rilis lebih dulu karena degradasi aman.

## 18. Catatan / Risiko

- **Watermark korup / jam device mundur** → bisa lewatkan record. Mitigasi:
  simpan watermark dari `updated_at` server (bukan jam device), dan sediakan
  force full refresh (6.3) untuk recovery.
- **Deletion** tak tertangani (sama seperti sekarang) — perlu tombstone bila
  nanti dibutuhkan; di luar scope.
- **Zona waktu:** selalu format/simpan watermark dalam UTC.

---

# Rencana: Aktifkan R8 (minify + shrinkResources) untuk Build Release Android (Fase 7)

Status: **DRAFT — menunggu review**
Tanggal: 2026-08-06

## 19. Konteks & Akar Masalah

Build release Android **tidak** mengaktifkan R8. Di
[android/app/build.gradle](../android/app/build.gradle#L56) blok `release`:
`minifyEnabled false`, `shrinkResources false`, dan **tidak ada** file
`android/app/proguard-rules.pro`. Akibatnya APK release lebih besar dan kode
Android/Java tidak di-shrink/optimize/obfuscate.

Mengaktifkan R8 berisiko **crash release-only** karena R8 bisa menghapus/obfuscate
kelas yang dipakai lewat refleksi/JNI. Dependency berisiko (dari `pubspec.yaml`):
GraphHopper 7.0 + JTS + hppc (routing, pure-Java tanpa consumer rules),
mobile_scanner (ML Kit), flutter_local_notifications, flutter_background_service,
in_app_update (Play Core), firebase_*, geolocator/location/permission_handler/
wakelock_plus, printing/pdf.

**Batasan lingkungan:** `flutter`/`gradle` CLI tidak tersedia di sandbox agent →
semua build & uji APK release dijalankan **user**. Agent hanya mengedit
`build.gradle` + `proguard-rules.pro` dan menambal keep rules dari log yang
dilaporkan user.

## 20. Keputusan Arsitektur

- Aktifkan **bertahap**: `minifyEnabled` dulu (uji) → baru `shrinkResources`.
- Basis `proguard-android-optimize.txt` + `proguard-rules.pro` custom.
- Keep rules konservatif untuk lib tanpa consumer rules + `-dontwarn` untuk
  dependency Java desktop (java.awt/javax) yang tak ada di Android.
- Uji di **APK release fisik** pada subsistem berisiko.
- Pastikan mapping Crashlytics ter-upload agar stacktrace release terbaca.

## 21. Dependency Graph

```
Task 7.1 proguard-rules.pro (keep rules)          ← fondasi
   └── Task 7.2 minifyEnabled true + proguardFiles
            └── Task 7.3 uji fungsional APK release (minify)   ← gate risiko
                     └── Task 7.4 shrinkResources true
                              └── Task 7.5 verifikasi mapping/ukuran
                                       └── Task 7.6 regresi penuh + rilis
```
Urutan: **7.1 → 7.2 → 7.3 → 7.4 → 7.5 → 7.6**.

## 22. Tugas

### Task 7.1 — Buat `android/app/proguard-rules.pro`
Buat keep rules lengkap untuk semua dependency sensitif. Belum ubah `build.gradle`
(R8 masih mati → tanpa risiko build). Isi draft:
```proguard
# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**
# Firebase / Crashlytics
-keep class com.google.firebase.** { *; }
-keepattributes *Annotation*,SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
# GraphHopper + JTS + hppc
-keep class com.graphhopper.** { *; }
-dontwarn com.graphhopper.**
-keep class com.carrotsearch.hppc.** { *; }
-dontwarn com.carrotsearch.hppc.**
-keep class org.locationtech.jts.** { *; }
-dontwarn org.locationtech.jts.**
-dontwarn java.awt.**
-dontwarn javax.**
-dontwarn org.slf4j.**
-dontwarn com.fasterxml.**
# flutter_local_notifications
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
# mobile_scanner / ML Kit
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
# in_app_update (Play Core)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
# printing / pdf
-dontwarn com.itextpdf.**
# Plugin lain (jaga-jaga)
-keep class com.baseflow.geolocator.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
-keep class id.flutter.flutter_background_service.** { *; }
# Umum
-keepattributes EnclosingMethod,InnerClasses,Signature
-keepclassmembers enum * { *; }
```
- **Acceptance:** file dibuat; semua dependency berisiko tercakup keep/dontwarn.
- **Verify:** review manual tiap paket `pubspec.yaml` native/refleksi tercakup.
- **Dependencies:** None · **Files:** `android/app/proguard-rules.pro` · **Scope:** S

### Task 7.2 — Aktifkan `minifyEnabled true` + `proguardFiles`
Ubah `buildTypes.release`: `minifyEnabled true`, `shrinkResources false` (dulu),
`proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'`.
- **Acceptance:** minify aktif + proguardFiles terpasang; shrinkResources masih false.
- **Verify (user):** `flutter build apk --release` sukses; jika `Missing class …`,
  tambahkan `-keep`/`-dontwarn` sesuai → build ulang; app launch tanpa crash.
- **Dependencies:** 7.1 · **Files:** `android/app/build.gradle` · **Scope:** S

### Checkpoint CP-I (setelah 7.1–7.2)
- [ ] Build release sukses, tanpa `Missing class` tersisa.
- [ ] App terbuka sampai home tanpa crash. Review dengan user.

### Task 7.3 — Smoke-test subsistem berisiko (APK release, minify)
Uji manual di perangkat fisik; tiap crash → tambah keep rule dari stacktrace.
- **Acceptance (jalan semua):** login+sync; GPS foreground+background+notif service;
  routing GraphHopper; FCM diterima/dibuka; PDF basemap render; scanner; in-app update.
- **Verify:** tiap subsistem hijau di APK release; crash → keep rule → rebuild.
- **Dependencies:** 7.2 · **Files:** `proguard-rules.pro` (iteratif) · **Scope:** M

### Task 7.4 — Aktifkan `shrinkResources true`
Nyalakan resource shrinking; bila ikon/aset yang dirujuk by-name hilang, tahan via
`android/app/src/main/res/raw/keep.xml`.
- **Acceptance:** shrinkResources true; ikon notifikasi & aset by-name tetap tampil.
- **Verify (user):** build sukses; ulangi smoke test 7.3 — semua tetap jalan.
- **Dependencies:** 7.3 · **Files:** `build.gradle`, (opsional) `res/raw/keep.xml` · **Scope:** S

### Checkpoint CP-J (setelah 7.3–7.4)
- [ ] Semua subsistem berisiko lulus di APK release; aset tak hilang. Review user.

### Task 7.5 — Verifikasi mapping Crashlytics & ukuran APK
- **Acceptance:** mapping ter-upload ke Crashlytics (deobfuscate); catat selisih
  ukuran APK sebelum/sesudah; crash sintetis → stacktrace terbaca.
- **Verify (user):** dashboard Crashlytics punya mapping; catat ukuran di todo.
- **Dependencies:** 7.4 · **Files:** (opsional) `build.gradle`
  `firebaseCrashlytics { mappingFileUploadEnabled true }` · **Scope:** XS–S

### Task 7.6 — Regresi penuh + siap rilis
- **Acceptance:** semua alur utama lulus di APK release; tak ada crash/ANR baru.
- **Verify (user):** full regression; `flutter build appbundle --release` sukses bila rilis AAB.
- **Dependencies:** 7.5 · **Scope:** M

### Checkpoint CP-K (Complete)
- [ ] Semua acceptance terpenuhi; APK lebih kecil & optimize tanpa crash; siap rilis.

## 23. Risiko & Mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| GraphHopper/JTS/hppc di-strip → routing crash release-only | High | Keep rules (7.1) + uji routing (7.3) |
| ML Kit (mobile_scanner) hilang → scanner crash | High | `-keep com.google.mlkit.**` + uji |
| local_notifications hilang → notif/FCM gagal | High | `-keep com.dexterous.**` + uji FCM |
| in_app_update (Play Core) di-strip | Medium | `-keep com.google.android.play.core.**` |
| shrinkResources hapus ikon notif by-name | Medium | Nyalakan terpisah (7.4) + `res/raw/keep.xml` |
| Stacktrace release ter-obfuscate | Medium | Verifikasi mapping Crashlytics (7.5) |
| CLI build tak ada di agent | Med | Build/uji dijalankan user; agent edit config saja |

## 24. Open Questions
- Rilis via **APK** atau **AAB (Play Store)**? (menentukan uji `appbundle` di 7.6)
- Perlu **obfuscation Dart** (`flutter build --obfuscate --split-debug-info`) juga?
  Itu terpisah dari R8 (sisi Dart) — bisa jadi task tambahan bila diinginkan.
