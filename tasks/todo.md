# TODO — Perbaikan Hasil Review (30 Sep 2026)

Plan: [plan.md](plan.md) · Plan sebelumnya: [plan-layers-logout.md](plan-layers-logout.md)
Mobile: `terestria` @ `main` · Backend: `gis-backend` @ `dev1` · commit per task, tanpa push/deploy

## Phase 1 — Watermark delta pull (Critical #1)
- [x] **T1 — Mobile: watermark tertahan sebelum record gagal** (S) — `failedAt − 1 µs`, fake server filter `>`, test pull kedua mengambil ulang
- [x] **T2 — Backend: `updated_after` inklusif (`__gte`)** (S) — helper + test mock lokal + kasus batas di test DB (CI) · gis-backend `e06041c` (dev1)

### Checkpoint 1
- [x] Test mobile & backend lokal hijau — **deploy backend `e06041c` memperbaiki app yang sudah terpasang** (test DB `ByProjectUpdatedAfterTests.test_batas_inklusif` jalan di CI)

## Phase 2 — Logout aman (Important #2, #3)
- [x] **T3 — `runExclusive` reentrant + semua jalur tulis sync eksklusif** (M) — pull, pullProjects, syncProject, twoWay
- [x] **T4 — Kunci DB selama reset logout** (S–M) — penulis terlambat gagal, tak membuat DB baru
- [x] **T5 — Draft koleksi dihitung saat logout & ikut cadangan ZIP** (M)

### Checkpoint 2
- [ ] Test hijau; device: pull lalu logout cepat → user B bersih; draft muncul di dialog & cadangan

## Phase 3 — Perbaikan kecil
- [x] **T6 — Reset state auto-sync saat logout** (S)
- [x] **T7 — Hasil share cadangan diperiksa (dismissed → peringatan)** (S)
- [x] **T8 — Emlid: connect baru mematikan auto-reconnect lama** (S)
- [x] **T9 — Edit record mempertahankan `serverKey` foto hasil sync** (S)
- [ ] **T10 — CSV `created_at` UTC + dokumentasi tindak lanjut** (XS)

### Checkpoint 3
- [ ] Test hijau; analyze 0 error; device: Emlid putus-sambung, share cadangan iOS, foto galeri iPhone JPEG

## Phase 4 — Butuh keputusan (belum dijadwalkan)
- [ ] D1 datum tinggi Emlid (elipsoid?) · D2 kebijakan konflik (a/b) · D3 kontak User-Agent tile

## Open questions (lihat plan.md)
1. Deploy backend T2 segera? *(ya)*  2. D1 → tunda  3. D2 → (a) sekarang, (b) spec terpisah  4. D3 → tunda
