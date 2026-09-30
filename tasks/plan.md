# Rencana: Perbaikan Hasil Review (Sync Watermark, Logout Aman, Perbaikan Kecil)

Status: **DRAFT — menunggu persetujuan** · Tanggal: 2026-09-30
Sumber: review 17 commit "review lapangan" (`c1002b5..fb40943`) — temuan #1–#9 + nit.
Plan sebelumnya (selesai): [plan-layers-logout.md](plan-layers-logout.md)

| Repo | Path | Branch | Catatan |
|---|---|---|---|
| Mobile | `D:\Developments\terestria` | `main` | Jangan stage `lib/config/api_config.dart` & `pubspec.yaml` (perubahan lokal user) |
| Backend | `D:\Developments\gis-backend` | `dev1` | Jangan stage `gisbackend/__pycache__/*.pyc` |

Commit per task di repo masing-masing; tidak ada push/deploy (dilakukan user).

## Overview
1. **Critical (#1)** — Record yang gagal disimpan saat pull tetap terlewat selamanya: mobile menahan
   watermark TEPAT di `updatedAt` record gagal, sedangkan backend memfilter `updated_at > nilai`
   (`mobile/views.py:884`), padahal kontrak (`docs/sync-delta-api-contract.md:35`) mewajibkan `>=`.
2. **Important (#2)** — Draft koleksi (titik digitasi + isian form) terhapus saat logout tanpa
   dihitung di dialog logout dan tanpa masuk cadangan ZIP.
3. **Important (#3)** — Pull manual & `syncProject` tidak eksklusif; logout hanya menunggu sync ≤30 dtk.
   Penulisan yang terlambat membuka ulang `geoform.db` baru → data user A terlihat oleh user B.
4. **Suggestion (#4–#6, #9) + nit** — state auto-sync terbawa ke user berikutnya, hasil share
   cadangan diabaikan, reconnect Emlid basi, edit record menghapus `serverKey` foto, CSV bukan UTC.
5. **Butuh keputusan (#7, #8, UA tile)** — datum tinggi, kebijakan konflik, kontak User-Agent tile.

## Architecture Decisions
- **Watermark diperbaiki di DUA sisi (independen, urutan deploy bebas).**
  - Mobile: bila ada record gagal, watermark = `failedAt − 1 µs` (tak pernah mundur) → record gagal
    selalu diambil ulang, baik server memakai `>` maupun `>=`.
  - Backend: `updated_at__gte` sesuai kontrak. Ini juga **memperbaiki app yang sudah terpasang**
    (versi lama menahan watermark di `failedAt`) begitu backend di-deploy. Biaya: record batas
    ikut terkirim lagi tiap delta pull — sudah di-dedup klien (tak disimpan ulang).
  - Test mobile memakai *fake server* yang benar-benar menerapkan filter `updated_after` seperti
    backend, bukan daftar respons berurutan (penyebab bug lolos test).
- **Semua jalur sync yang MENULIS DB lewat `runExclusive`**, yang dibuat *reentrant* (Zone value
  berisi token eksekusi aktif): panggilan bersarang dari dalam body eksklusif langsung jalan (tanpa
  deadlock), continuation basi setelah body selesai tidak dianggap reentrant.
- **DB dikunci selama reset logout.** `DatabaseService.lockForReset()` menutup koneksi dan membuat
  akses `database` melempar error sampai langkah terakhir reset membuka kunci. Penulis terlambat
  gagal keras (dicatat) alih-alih membuat `geoform.db` baru berisi data user A.
- **Draft = data user**: dihitung di dialog logout dan ikut cadangan ZIP.
- Perbaikan kecil dibuat testable lewat fungsi murni / injeksi (share, merge serverKey foto).

## Dependency Graph
```
Phase 1  T1 mobile watermark (−1µs + fake server)      T2 backend updated_at__gte   [independen]
Phase 2  T3 runExclusive reentrant + jalur tulis ─► T4 kunci DB saat reset
         T5 draft dihitung & dicadangkan                                            [independen]
Phase 3  T6 reset auto-sync · T7 hasil share · T8 Emlid · T9 merge serverKey · T10 CSV UTC + docs
Phase 4  D1 datum tinggi · D2 kebijakan konflik · D3 kontak UA   (menunggu keputusan)
```

## Task List

### Phase 1 — Watermark delta pull (Critical #1)

#### T1: Mobile — watermark tertahan SEBELUM record gagal (S)
- AC:
  - `PullWatermarkTracker.nextWatermark` mengembalikan `failedAt − 1 µs` bila ada record gagal;
    tetap tak pernah mundur dari watermark sebelumnya; perilaku tanpa kegagalan tak berubah.
  - Test memakai `_FakeServer` (menyimpan record, mem-parse `updated_after` dari endpoint, filter
    **`>`** seperti backend sekarang): pull #1 record `bad` gagal → pull #2 (tak gagal lagi) →
    `bad` tersimpan. Test ini **RED** pada kode sekarang.
  - Test tracker "record gagal menahan watermark" diperbarui; komentar "filter server inklusif"
    (`sync_service.dart:867-870`, `1219-1221`) dikoreksi.
  - `docs/sync-delta-api-contract.md`: catatan implementasi klien (tahan di `failedAt − 1 µs`).
- Verifikasi: `flutter test test/services/sync_integrity_test.dart` (RED → GREEN), full suite.
- Files: `lib/services/sync_service.dart`, `test/services/sync_integrity_test.dart`,
  `docs/sync-delta-api-contract.md`.

#### T2: Backend — `updated_after` inklusif sesuai kontrak (S)
- AC:
  - Helper `_apply_updated_after(queryset, raw)` → `filter(updated_at__gte=parsed)`; string tak
    valid diabaikan (perilaku lama); dipakai `by_project` (jalur `count_only` ikut konsisten).
  - Unit test mock ORM (jalan lokal) di `mobile/tests_pull_filter.py`: `__gte` dipanggil dengan
    datetime ter-parse; nilai tak valid → queryset tak difilter.
  - `ByProjectUpdatedAfterTests` (DB, CI-only): tambah kasus batas — record `updated_at == cutoff`
    **ikut** dikembalikan; docstring diperbarui.
- Verifikasi (conda `django-env` + GDAL di PATH):
  `"$PY" manage.py check` · `"$PY" -m unittest mobile.tests_pull_filter`; test DB di CI.
- Files: `gis-backend/mobile/views.py`, `mobile/tests_pull_filter.py`, `mobile/tests_verification.py`.

### Checkpoint 1
- [ ] Test mobile & backend (lokal) hijau; `flutter analyze` 0 error.
- [ ] Catatan deploy untuk user: T2 memperbaiki app terpasang begitu backend di-deploy.

### Phase 2 — Logout aman (Important #2, #3)

#### T3: `runExclusive` reentrant + semua jalur tulis sync eksklusif (M)
- AC:
  - `runExclusive` reentrant (Zone value = token eksekusi aktif): panggilan bersarang langsung jalan;
    continuation setelah body selesai tidak dianggap reentrant.
  - `pullGeoDataFromServer`, `pullProjectsFromServer`, `syncProject`, `performTwoWaySync` lewat
    `runExclusive`; `isSyncing` true selama pull.
  - Test: (a) bersarang tak deadlock (dengan timeout test); (b) pull manual menunggu upload yang
    sedang berjalan; (c) `syncProjectAndData` (memanggil `syncProject` di dalam) tetap selesai.
- Verifikasi: test baru `test/services/sync_exclusive_test.dart`, full suite.
- Files: `lib/services/sync_service.dart`, test baru.

#### T4: Kunci DB selama reset logout (S–M)
- AC:
  - `DatabaseService.lockForReset()` (tutup + kunci) & `unlockAfterReset()`; saat terkunci getter
    `database` melempar `DatabaseResetInProgress` tanpa membuka/membuat berkas.
  - Langkah reset `databases` mengunci; langkah terakhir baru `unlock` selalu berjalan (walau
    langkah lain gagal) → user B bisa login & DB baru dibuat normal.
  - Test: getter melempar saat terkunci & normal setelah dibuka; urutan langkah (`databases`
    sebelum `files`, `unlock` terakhir); `user_switch_test` tetap hijau.
- Verifikasi: test app_reset + full suite.
- Files: `lib/services/database_service.dart`, `lib/services/app_reset/app_reset_service.dart`,
  `test/services/app_reset/*`.

#### T5: Draft koleksi dihitung saat logout & ikut cadangan (M)
- AC:
  - `CollectionDraftService.listDrafts()` → draft per project (abaikan kosong/rusak).
  - `PendingLogoutData.drafts`; dialog menampilkan "N unsaved collection draft(s)"; hanya ada
    draft → tetap dialog *pending* (bukan konfirmasi biasa); muat di 360 dp.
  - Cadangan ZIP: `projects/<name>/draft.json` (+ geometri bila titik cukup) dan `totals.drafts`
    di manifest; README diperbarui.
- Verifikasi: `logout_guard_test`, `local_backup_test`, test `listDrafts`, full suite.
- Files: `lib/services/collection_draft_service.dart`, `lib/services/app_reset/logout_guard.dart`,
  `lib/services/app_reset/local_backup_service.dart`, tests.

### Checkpoint 2
- [ ] Test hijau; analyze 0 error.
- [ ] Device: mulai Pull di detail project → kembali → logout segera → login user B → tak ada data A.
- [ ] Device: digitasi 3 titik tanpa simpan → Logout → dialog menyebut draft; cadangan berisi draft.

### Phase 3 — Perbaikan kecil (Suggestion #4–#6, #9, nit)

#### T6: Reset state auto-sync saat logout (S)
- AC: `AutoSyncService.reset()` mengosongkan hitungan gagal, waktu gagal terakhir, dan `lastRun`;
  dipanggil langkah reset `accounts`. Test: setelah reset, run berikutnya tanpa backoff.
- Files: `lib/services/auto_sync_service.dart`, `app_reset_service.dart`, test.

#### T7: Hasil share cadangan diperiksa (S)
- AC: `ShareResultStatus.dismissed` → kembalikan false + peringatan "Backup was not saved";
  `unavailable` (Android) → pesan netral sekarang. Fungsi share & service dapat disuntik; widget test.
- Files: `lib/widgets/backup/backup_actions.dart`, test.

#### T8: Emlid — connect baru mematikan auto-reconnect lama (S)
- AC: awal `connectEmlidTCP` mematikan `_autoReconnect` & timer reconnect; jalur "lost right after
  connecting" tak menjadwalkan reconnect. Test loopback `ServerSocket` (server menutup koneksi
  segera): connect → false & tak ada reconnect terjadwal (getter `@visibleForTesting`).
- Files: `lib/services/location_service_v2.dart`, test baru (±4 dtk, I/O nyata).

#### T9: Edit record tak menghapus `serverKey` foto hasil sync (S)
- AC: fungsi murni `mergeUploadedPhotoKeys(edited, latest, project)` menyalin `serverKey`/`serverUrl`
  foto yang sama (`localPath`) dari versi DB terbaru; `_saveChanges` memakai versi terbaru sebelum
  menyimpan. Test fungsi murni.
- Files: `lib/services/photo_sync_service.dart` (atau util baru), `edit_geo_data_screen.dart`, test.

#### T10: CSV `created_at` UTC + dokumentasi tindak lanjut (XS)
- AC: `GeoExport.csv` menulis `created_at` UTC; `geo_export_test` diperbarui;
  `docs/review-lapangan.md` bagian "Tindak lanjut review 30 Sep" (status #1–#9).
- Files: `lib/services/export/geo_export.dart`, `test/services/geo_export_test.dart`, `docs/review-lapangan.md`.

#### T11: Tinggi Emlid seragam elipsoid — keputusan D1 (S)
- Diputuskan user (30 Sep): **elipsoid**.
- AC: NMEA GGA → `altitude = H + N` (kolom 9 + kolom 11); tanpa N → tetap H + dicatat sekali;
  LLH/XYZ tak berubah (sudah elipsoid). Test parser.
- Files: `lib/services/gps/emlid_parsers.dart`, `test/services/emlid_parsers_test.dart`, docs.

### Checkpoint 3 — Complete
- [ ] `flutter test` hijau; `flutter analyze` 0 error & tak ada warning baru.
- [ ] Device: Emlid dicabut 30 dtk → tersambung lagi; Connect ulang ke IP salah → tak ada reconnect
      "hantu"; iOS: tutup share sheet cadangan → peringatan; foto galeri iPhone tersimpan JPEG.

### Phase 4 — Butuh keputusan (tidak dikerjakan sebelum diputuskan)
- **D1 — Datum tinggi (#7).** ✅ Diputuskan **elipsoid** (30 Sep) → dikerjakan sebagai T11.
  Catatan: GPS HP Android = elipsoid, iOS = MSL — di luar cakupan.
- **D2 — Kebijakan konflik (#8).** Server upsert tanpa cek versi (`views.py:675-686`), jadi upload
  lokal menimpa editan rekan. Opsi: (a) biarkan "lokal menang" + dokumentasikan; (b) *optimistic
  concurrency*: server membalas 409 bila versinya lebih baru dari versi dasar klien — perlu kolom
  `serverUpdatedAt` di DB mobile (migrasi v6) + UI konflik → **spec terpisah**. Usul: (a) sekarang, (b) lewat `/spec`.
- **D3 — Kontak User-Agent tile** (`api_config.dart:14`): butuh email/URL publik yang benar.

## Risks and Mitigations
| Risk | Impact | Mitigation |
|---|---|---|
| `runExclusive` reentrant salah → deadlock atau eksklusivitas bocor | High | Token per eksekusi di Zone; test bersarang dengan timeout + test urutan; semua jalur lewat satu pintu |
| Kunci DB menggagalkan jalur sah saat reset (mis. flush tracking) | Med | Flush tracking terjadi di langkah `tracking` sebelum kunci; `flushNow` tak pernah melempar; unlock selalu dijalankan |
| Backend `>=` mengirim ulang record batas tiap delta | Low | Klien dedup (tak disimpan ulang) — dicek test; 1 record per pull |
| Klien `−1 µs` tak cocok dengan presisi server | Low | Postgres & Dart VM sama-sama mikrodetik; ISO8601 6 digit didukung `parse_datetime` |
| Test Emlid memakai socket nyata → lambat/flaky | Low | Loopback saja, tanpa jaringan eksternal; batas waktu longgar |
| Menyentuh perubahan lokal user (`api_config.dart`, `pubspec.yaml`, `.pyc`) | Med | Stage per file eksplisit; tak pernah `git add -A` |

## Out of Scope
Tombstone hapus ke server (A22), aksi Stop di notifikasi (A23), mode kontras tinggi (B2), progres MB
per foto (B6), pergantian penyedia tile berlisensi (A34) — tetap sesuai status di `docs/review-lapangan.md`.

## Open Questions (default dipakai bila disetujui tanpa catatan)
1. Deploy backend T2 segera setelah merge ke `dev1`? *(default: ya — memperbaiki app terpasang)*
2. D1 datum tinggi Emlid → elipsoid? *(default: tunda sampai diputuskan)*
3. D2 konflik → (a) sekarang, (b) spec terpisah? *(default: ya)*
4. D3 kontak UA tile? *(default: tunda; perlu email/URL dari user)*
