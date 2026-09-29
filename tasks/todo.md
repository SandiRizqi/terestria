# TODO — Perbaikan Multi-Project Tracking (TrackingEngine)

Plan: [plan.md](plan.md) · Spec: [SPEC.md](../SPEC.md) · Branch: `main`

## Phase 1 — Hotfix: titik terekam lagi (C1–C3)
- [x] **Task 1 — Status background service nyata** (S) ✅ 7 test — isolate lapor `isRunning:false` sebelum `stopSelf`; `start()` verifikasi ke plugin
- [x] **Task 2 — TrackingEngine keep-alive app-level** (M) ✅ 8 test engine — heartbeat & start/stop service pindah dari layar ke engine (0→1 / 1→0)
- [x] **Task 3 — Restore & re-entry terhubung engine** (S) ✅ 2 test — restore = paused; `_isPaused` dipulihkan; Resume menyalakan engine

### Checkpoint A (device)
- [x] Test + analyze hijau (52 test tracking)
- [ ] Start A → back → Start B → keduanya bertambah ≥2 menit dengan layar tertutup
- [ ] Stop A → A berhenti, B lanjut; Stop B → service & notifikasi mati
- [ ] Review user sebelum Phase 2

## Phase 2 — Refactor: satu sumber kebenaran (I1–I5)
- [ ] **Task 4 — Status sesi recording/paused/pendingSave** (M) — finish → pendingSave; cap = recording+paused
- [ ] **Task 5 — Sesi terikat provider + feed tunggal di engine** (M) — DB v5 `provider`; Emlid & phone di-fan-out oleh engine
- [ ] **Task 6 — DataCollectionScreen = view sesi** (M) — `_draftPoints` dari sesi; hapus append ganda & sync
- [ ] **Task 7 — Bersihkan state global + notifikasi tunggal** (M) — hapus `isActivelyTracking` dkk.; label notifikasi dari engine
- [ ] **Task 8 — Skenario end-to-end (fake)** (S) — regresi C1 terkunci

## Phase 3 — UX pengelola tracking
- [ ] **Task 9 — Panel "Tracking Aktif" interaktif** (M) — chip status, jeda/lanjut, durasi & titik live, ringkasan banner per status

### Checkpoint B (complete)
- [ ] Semua test hijau; analyze 0 error
- [ ] Manual Android + iOS: 1-project, multi 2–3, layar tertutup ≥5 menit, kill/restore, Emlid, cap, ganti provider

## Keputusan
Restore → paused · pendingSave di luar cap · provider per sesi · semua phase berurutan (tes device oleh user setelah build)
