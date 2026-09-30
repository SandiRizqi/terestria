# Rencana: Konflik Sync (D2), Project Nonaktif Menolak Data, Pesan Error Push

Status: **DRAFT — menunggu persetujuan** · Tanggal: 2026-09-30
Permintaan user: (1) jalankan D2 (konflik editan), (2) project yang `is_active=False` menolak push
data dengan pesan jelas, (3) di mobile, push yang gagal menampilkan pesan error-nya.
Plan sebelumnya (selesai): [plan-review-fixes.md](plan-review-fixes.md)

| Repo | Path | Branch | Catatan |
|---|---|---|---|
| Backend | `D:\Developments\gis-backend` | `dev1` | Jangan stage `gisbackend/__pycache__/*.pyc` |
| Mobile | `D:\Developments\terestria` | `main` | Jangan stage `lib/config/api_config.dart` & `pubspec.yaml` (perubahan lokal user) |

## Temuan dari kode (dasar keputusan)
- `Project.is_active = BooleanField(default=True)` **sudah ada** di backend (`mobile/models.py`), sudah
  tampil & bisa difilter di admin — **tidak perlu migrasi**. Yang belum ada: penegakan saat push.
- Endpoint upsert geodata menangkap SEMUA exception jadi **HTTP 500** generik (`views.py:708`) →
  penolakan harus dicek eksplisit di view, bukan dilempar dari serializer.
- Server mengisi `GeoData.updated_at` dengan waktu SERVER di setiap simpan (serializer) → dasar
  versi yang tepat untuk deteksi konflik. Upsert sekarang tanpa cek versi (siapa terakhir menang).
- Mobile memetakan SEMUA 403 jadi "You do not have permission…" (`sync_service.dart:1215`), dan
  tombol Sync di beranda / sync sebelum logout / status auto-sync hanya menampilkan ringkasan
  ("Data: 3/5 synced") tanpa alasan gagal. Hanya detail project yang sudah menampilkan alasan.

## Architecture Decisions
1. **Project nonaktif** — geodata push (upsert & `bulk_sync`) ke project `is_active=False` →
   **HTTP 403** `{"success": false, "error_code": "project_inactive", "message": "Project \"X\" is not
   accepting data right now (inactive)."}`. Sinkron metadata project (form) TIDAK diblokir.
   Admin: `is_active` bisa diubah langsung dari daftar project (`list_editable`).
2. **D2 = optimistic concurrency** (versi = `updated_at` server):
   - Mobile menyimpan per record `serverUpdatedAt` = versi server terakhir yang dilihat (dari pull
     atau respons push). Push mengirim `base_updated_at`; opsi `force: true` untuk "pakai versi saya".
   - Server: record ada & `updated_at > base_updated_at` & bukan `force` → **HTTP 409**
     `{"error_code": "conflict", "message": "...", "data": <versi server>}`.
   - Tanpa `base_updated_at` (app versi lama, upload pertama, retry setelah respons hilang) →
     perilaku lama. **Backward-compatible**: app terpasang tak terdampak.
   - Mobile menyimpan versi server di tabel `sync_conflicts`; record tetap belum tersinkron dan
     **tidak diunggah otomatis** sampai user memilih **Keep mine** (push `force`) atau **Use server
     version** (ganti lokal dengan versi server). Pull juga mendeteksi konflik lebih awal (server
     berubah sejak `serverUpdatedAt` & lokal punya editan).
3. **Pesan error push terlihat di semua tempat**: `error_code` dari server diutamakan (pesan
   `project_inactive` tampil apa adanya); alasan gagal terakhir disimpan per record
   (`lastSyncError`) dan tampil di daftar data; satu dialog hasil sync bersama untuk Beranda,
   sync sebelum logout, dan Readiness; status auto-sync di beranda menyebut alasan pertama.
   Satu record `project_inactive` → sisa record project itu dilewati di run yang sama (pesan sama).
4. **Migrasi DB mobile v6** (satu kali, idempoten): kolom `geo_data.serverUpdatedAt`,
   `geo_data.lastSyncError`, tabel `sync_conflicts`. Kolom dicek lewat `PRAGMA table_info` sebelum
   `ALTER` (pola v5 `needsProviderColumn`), diuji sebagai fungsi murni.

## Dependency Graph
```
B1 backend project_inactive (403) ──────────────┐
B2 backend base_updated_at / force / 409 ───────┤ (kontrak API)
                                                 ▼
M1 DB v6 + model (serverUpdatedAt, lastSyncError, sync_conflicts)
 └─► M2 push: kirim base, simpan versi server, error_code, lastSyncError, skip project nonaktif
      └─► M3 konflik: simpan 409 & konflik saat pull, keluarkan dari upload otomatis, resolve API
           ├─► M4 UI pesan error (dialog hasil sync bersama, status auto-sync, error per record)
           └─► M5 UI konflik (banner + sheet Keep mine / Use server) + cadangan ZIP + dokumentasi
```

## Task List

### Phase 1 — Backend (gis-backend @ dev1)

#### B1: Project nonaktif menolak push geodata (S)
- AC:
  - Helper `_project_inactive_response(project)` / cek di `GeoDataViewSet.create` (sebelum
    serializer) & per item `bulk_sync`: project `is_active=False` → 403 + `error_code:
    project_inactive` + pesan berisi nama project; item bulk lain tetap diproses.
  - Project tak ada → perilaku lama. Upsert project (form) tak terpengaruh.
  - Admin: `list_editable = ('is_active',)`.
- Verifikasi: test mock (lokal) untuk create & bulk; kasus DB di CI; `manage.py check`.
- Files: `mobile/views.py`, `mobile/admin.py`, `mobile/tests_push_rules.py` (baru), `mobile/tests.py` (CI).

#### B2: Deteksi konflik versi saat push (S–M)
- AC:
  - Upsert & `bulk_sync` menerima `base_updated_at` (ISO) & `force` (bool).
  - Record ada, `base` valid, `updated_at > base`, bukan `force` → 409 `error_code: conflict` +
    `data` = versi server (format mobile); bulk: item konflik masuk daftar error dengan `data`.
  - `base` kosong/tak valid → perilaku lama. Respons sukses tetap memuat `data.updatedAt` (versi baru).
- Verifikasi: test mock helper `_version_conflict(instance, base_raw, force)` + wiring view; CI DB.
- Files: `mobile/views.py`, test; kontrak: `terestria/docs/sync-push-contract.md` (baru).

### Checkpoint 1
- [ ] Test lokal backend hijau; `manage.py check` bersih; kontrak push terdokumentasi.

### Phase 2 — Mobile fondasi (terestria @ main)

#### M1: Migrasi DB v6 + model (M)
- AC: `_databaseVersion = 6`; `_onCreate` & `_onUpgrade` membuat kolom `serverUpdatedAt INTEGER`,
  `lastSyncError TEXT` di `geo_data` dan tabel `sync_conflicts(geoDataId PK, projectId, serverJson,
  detectedAt)`; upgrade idempoten (cek kolom via PRAGMA — fungsi murni teruji); `GeoData` punya
  `serverUpdatedAt` (JSON & baris DB, bolak-balik UTC); pull mengisi `serverUpdatedAt`.
- Verifikasi: test fungsi kolom-hilang, mapping baris/JSON; full suite. Manual: upgrade dari v5 di HP.
- Files: `database_service.dart`, `geo_data_model.dart`, `storage_service.dart`, tests.

#### M2: Push membawa versi & melaporkan error server (M)
- AC:
  - Payload push memuat `base_updated_at` (dari `serverUpdatedAt`); sukses → simpan
    `serverUpdatedAt` dari respons & kosongkan `lastSyncError` (update bersyarat tetap).
  - `SyncResult.errorCode`; `_serverErrorMessage` mengutamakan `error_code` (`project_inactive` →
    pesan server apa adanya, bukan "no permission").
  - Gagal → `lastSyncError` disimpan per record. Batch: `project_inactive` → sisa record project
    itu dilewati dengan pesan yang sama (tanpa request).
- Verifikasi: test sync (fake API 403 project_inactive, 200 dengan updatedAt, payload berisi base).
- Files: `sync_service.dart`, `storage_service.dart`/`database_service.dart`, tests.

#### M3: Konflik — simpan, cegah upload otomatis, resolve (M)
- AC:
  - 409 → versi server disimpan di `sync_conflicts`; `SyncResult.isConflict`; record tetap unsynced.
  - Pull: server berubah sejak `serverUpdatedAt` & lokal belum tersinkron → konflik disimpan.
  - Upload otomatis & "sync semua" melewati record berkonflik (dilaporkan sebagai konflik).
  - `SyncService.resolveKeepMine(id)` (push `force`) & `resolveUseServer(id)` (ganti lokal dengan
    versi server, synced) → konflik dihapus.
- Verifikasi: test sync (409 tersimpan, dilewati auto, resolve dua arah, pull mendeteksi).
- Files: `sync_service.dart`, `database_service.dart`, `storage_service.dart`, tests.

### Checkpoint 2
- [ ] Test hijau; analyze 0 error; payload & respons cocok dengan kontrak B1/B2.

### Phase 3 — Mobile UI

#### M4: Pesan error push terlihat (M)
- AC: dialog hasil sync bersama (alasan dikelompokkan, "Retry failed") dipakai Beranda, sync
  sebelum logout, Readiness; status auto-sync di beranda menyebut alasan pertama; daftar data
  menampilkan `lastSyncError` pada record yang gagal; muat di 360 dp.
- Verifikasi: widget test dialog & item; full suite.
- Files: `widgets/sync/sync_result_dialog.dart` (baru), `home_status_section.dart`, `menu_screen.dart`,
  `field_readiness_screen.dart`, `geo_data_list_item.dart`, `project_detail_screen.dart`, tests.

#### M5: UI konflik + cadangan + dokumentasi (M)
- AC: detail project menampilkan banner "N records were changed on the server" → sheet per
  record (ringkasan lokal vs server: waktu, kolektor, field yang beda) dengan **Keep mine** /
  **Use server version**; cadangan ZIP menyertakan `conflicts.json` (versi server);
  `docs/review-lapangan.md` baris #8 diperbarui.
- Verifikasi: widget test sheet (dua aksi memanggil resolve), test cadangan; full suite.
- Files: `widgets/sync/conflict_sheet.dart` (baru), `project_detail_screen.dart`,
  `local_backup_service.dart`, docs, tests.

### Checkpoint 3 — Complete
- [ ] `flutter test` hijau; analyze 0 error & tak ada warning baru; test lokal backend hijau.
- [ ] Device: set project nonaktif di admin → push → pesan "not accepting data" tampil di Beranda,
      detail project, dan pada record; aktifkan lagi → sync berhasil.
- [ ] Device (2 HP): edit record yang sama di dua HP → yang kedua mendapat konflik → Keep mine /
      Use server bekerja; auto-sync tak mengulang konflik.
- [ ] Device: upgrade app dari versi sebelumnya (DB v5 → v6) tanpa kehilangan data.

## Risks and Mitigations
| Risk | Impact | Mitigation |
|---|---|---|
| Migrasi DB v6 gagal di HP terpasang | High | Hanya menambah kolom/tabel; idempoten (cek PRAGMA); tak menyentuh data; uji manual upgrade v5→v6 |
| Konflik palsu karena jam/presisi | Med | Versi = `updated_at` SERVER (bukan jam HP); dibandingkan apa adanya (mikrodetik) |
| Record berkonflik diunggah ulang terus oleh auto-sync | Med | Dikeluarkan dari upload otomatis sampai diselesaikan |
| App lama menerima 403 project nonaktif → pesan generik "no permission" | Low | Diterima sampai user update; data tetap aman di HP |
| Dialog error baru mengganggu (auto-sync) | Low | Auto-sync tak memunculkan dialog; hanya status di beranda |

## Out of Scope
Menandai project nonaktif di daftar project mobile (blokir koleksi sebelum push), penggabungan
otomatis per field (merge), tombstone hapus ke server.

## Open Questions (default dipakai bila disetujui tanpa catatan)
1. Resolusi konflik per record **Keep mine / Use server version** (manual)? *(default: ya)*
2. Metadata project (form) tetap boleh di-sync walau project nonaktif? *(default: ya — hanya data yang ditolak)*
3. Status HTTP project nonaktif = **403** + `error_code: project_inactive`? *(default: ya)*
4. Deploy backend (B1, B2) sebelum rilis app baru? *(default: ya — backward-compatible)*
