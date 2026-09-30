# TODO — Konflik Sync (D2), Project Nonaktif, Pesan Error Push (30 Sep 2026)

Plan: [plan.md](plan.md) · Plan sebelumnya: [plan-review-fixes.md](plan-review-fixes.md)
Backend: `gis-backend` @ `dev1` · Mobile: `terestria` @ `main` · commit per task, tanpa push/deploy

## Phase 1 — Backend
- [ ] **B1 — Project nonaktif menolak push geodata (403 `project_inactive`)** (S) — upsert + bulk_sync, admin list_editable
- [ ] **B2 — Deteksi konflik versi saat push (409 `conflict`)** (S–M) — `base_updated_at`, `force`, kontrak push

### Checkpoint 1
- [ ] Test lokal backend hijau; kontrak push terdokumentasi

## Phase 2 — Mobile fondasi
- [ ] **M1 — Migrasi DB v6 + model** (M) — serverUpdatedAt, lastSyncError, sync_conflicts
- [ ] **M2 — Push membawa versi & melaporkan error server** (M) — error_code, lastSyncError, skip project nonaktif
- [ ] **M3 — Konflik: simpan, cegah upload otomatis, resolve** (M)

### Checkpoint 2
- [ ] Test hijau; payload & respons cocok kontrak

## Phase 3 — Mobile UI
- [ ] **M4 — Pesan error push terlihat** (M) — dialog hasil sync bersama, status auto-sync, error per record
- [ ] **M5 — UI konflik + cadangan + dokumentasi** (M)

### Checkpoint 3
- [ ] Test hijau; device: project nonaktif, konflik 2 HP, upgrade DB v5→v6

## Open questions (lihat plan.md)
1. Konflik: Keep mine / Use server *(ya)*  2. Form project nonaktif tetap sync *(ya)*
3. 403 + `project_inactive` *(ya)*  4. Deploy backend dulu *(ya)*
