# TODO — Konflik Sync (D2), Project Nonaktif, Pesan Error Push (30 Sep 2026)

Plan: [plan.md](plan.md) · Plan sebelumnya: [plan-review-fixes.md](plan-review-fixes.md)
Backend: `gis-backend` @ `dev1` · Mobile: `terestria` @ `main` · commit per task, tanpa push/deploy

## Phase 1 — Backend
- [x] **B1 — Project nonaktif menolak push geodata (403 `project_inactive`)** (S) — upsert + bulk_sync, admin list_editable · gis-backend `79fa50c`
- [x] **B2 — Deteksi konflik versi saat push (409 `conflict`)** (S–M) — `base_updated_at`, `force`, kontrak push · gis-backend `2cfd135`

### Checkpoint 1
- [x] Test lokal backend hijau (28); kontrak push: `docs/sync-push-contract.md`; test DB (`mobile.tests_push_db`) jalan di CI

## Phase 2 — Mobile fondasi
- [x] **M1 — Migrasi DB v6 + model** (M) — serverUpdatedAt, lastSyncError, sync_conflicts
- [x] **M2 — Push membawa versi & melaporkan error server** (M) — error_code, lastSyncError, skip project nonaktif
- [x] **M3 — Konflik: simpan, cegah upload otomatis, resolve** (M)

### Checkpoint 2
- [x] Test hijau; payload (`base_updated_at`, `force`) & respons (`data.updatedAt`, `error_code`, 409 `data`) cocok kontrak — diuji di kedua sisi

## Phase 3 — Mobile UI
- [x] **M4 — Pesan error push terlihat** (M) — dialog hasil sync bersama, status auto-sync, error per record
- [x] **M5 — UI konflik + cadangan + dokumentasi** (M)

### Checkpoint 3
- [ ] Test hijau; device: project nonaktif, konflik 2 HP, upgrade DB v5→v6

## Open questions (lihat plan.md)
1. Konflik: Keep mine / Use server *(ya)*  2. Form project nonaktif tetap sync *(ya)*
3. 403 + `project_inactive` *(ya)*  4. Deploy backend dulu *(ya)*
