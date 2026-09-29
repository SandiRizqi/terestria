# Rencana Perbaikan: Multi-Project Tracking — TrackingEngine

Status: **DRAFT — menunggu review**
Tanggal: 2026-09-29 · Branch: `main` (commit per task)
Sumber: hasil review multi-project tracking (C1–C3, I1–I5). Spec induk: [SPEC.md](../SPEC.md)

## Overview
Titik GPS tidak terekam per project karena **siklus hidup service GPS masih
dimiliki layar `DataCollectionScreen`**. Heartbeat hanya dikirim layar, jadi
service background mematikan diri ±15 dtk setelah layar ditutup (C1). Status
`_isRunning` basi membuat Start berikutnya tak menyalakan service (C2). Sesi yang
dipulihkan tak pernah dihubungkan ke GPS (C3).

Perbaikannya: pindahkan kepemilikan feed GPS ke **`TrackingEngine`** di level app.
Engine menyala saat ada sesi *recording* dan mati saat tak ada. Layar hanya
**menampilkan** sesi dan **memberi perintah** ke manajer.

## Architecture Decisions
- **TrackingEngine = satu-satunya pemilik feed.** Engine memegang start/stop
  background service, heartbeat, langganan Emlid, log GPS, dan teks notifikasi.
  Layar tak lagi memanggil `startBackgroundTracking`, `sendHeartbeat`, atau
  `start/stopActiveTracking`.
- **Keputusan berbasis jumlah sesi recording.** Engine menyala saat
  `recordingCount` 0→1 dan mati saat 1→0. Ini menggantikan
  `shouldStopBackgroundOnFinish` dan `onAllSessionsStopped`.
- **Status service nyata, bukan cache.** Isolate mengirim
  `service_status{isRunning:false}` sebelum setiap `stopSelf()`. `start()` juga
  mengecek `FlutterBackgroundService().isRunning()`.
- **Status sesi eksplisit:** `recording | paused | pendingSave`.
  - Cap dihitung dari `recording + paused`.
  - `pendingSave` = sudah Stop, belum disimpan. Status ini tak memblokir Start,
    tak menerima titik, dan tampil di panel dengan Simpan/Buang.
  - Kolom DB `paused` (INTEGER) dipakai ulang: 0/1/2, tanpa migrasi.
- **Sesi terikat provider saat Start** (phone/emlid). Titik hanya masuk ke sesi
  dengan provider yang sama, jadi RTK tak tercampur GPS HP. Butuh kolom
  `provider` (DB v5).
- **Satu sumber data titik:** `TrackingSession.points`. Layar menggambar jalur
  dari sesi. `_collectedPoints` hanya untuk mode manual/drawing tanpa sesi.
  Mekanisme `_syncCollectedFromSession` dan append ganda dihapus.
- **Restore setelah app di-kill → sesi `paused`.** User menekan "Lanjutkan" di
  layar project atau panel. Ini aman untuk alur izin (iOS harus di foreground).
- **Uji tanpa dependency baru.** `pubspec.yaml` tidak disentuh (ada perubahan
  lokal user). Engine menerima *port* yang bisa diganti fake (start/stop service,
  heartbeat, timer factory), dan test memanggil `tick()` manual.

## Dependency Graph
```
T1 status service nyata ──┐
                          ├─► T2 TrackingEngine (keep-alive app-level) ─► T3 restore/re-entry
TrackingSessionManager ───┘                 │
                                            ├─► T4 status sesi (recording/paused/pendingSave)
                                            │        └─► T5 provider binding + feed tunggal (Emlid & phone)
                                            │                 └─► T6 layar = view sesi
                                            └─► T7 bersihkan state global + notifikasi
                                                          └─► T8 skenario end-to-end (fake) + manual device
```

## Task List

### Phase 1 — Hotfix: titik terekam lagi (C1–C3)

#### Task 1: Status background service yang nyata
**Description:** Hapus `_isRunning` yang basi. Isolate memberi tahu app setiap
kali berhenti sendiri (heartbeat timeout, lokasi mati, error, `stop_service`),
dan `start()` memverifikasi status ke plugin sebelum menganggap service
"already running".

**Acceptance criteria:**
- [ ] Setiap jalur `stopSelf()` di `_onStart` mengirim `service_status{isRunning:false}` lebih dulu.
- [ ] `start()` memanggil `FlutterBackgroundService().isRunning()` saat cache bilang "running". Bila ternyata mati, cache direset lalu service dinyalakan ulang.
- [ ] Listener `location_update` dipasang ulang setelah restart (tak ada listener ganda).

**Verification:**
- [ ] Unit: helper murni `needsRestart(cached, actual)` diuji.
- [ ] `flutter analyze lib/services/background/` bersih.
- [ ] Manual: Start → tunggu self-stop (matikan heartbeat) → Start lagi → log "Background service started", titik masuk.

**Dependencies:** None
**Files:** `lib/services/background/background_tracking_service.dart`, `test/services/background/background_running_state_test.dart`
**Scope:** S

#### Task 2: TrackingEngine — keep-alive di level app
**Description:** Buat `TrackingEngine` (singleton) yang mendengarkan manajer.
- Saat `activeCount` 0→1: pastikan service jalan dan mulai heartbeat app-level (5 dtk).
- Saat 1→0: hentikan heartbeat dan service.

Layar tak lagi mengurus heartbeat atau service:
- `_startHeartbeat`/`_stopHeartbeat` dan `start/stopBackgroundTracking` dihapus dari layar.
- Start di layar = `manager.start` + `await engine.ensureRunning()`. Bila gagal: rollback sesi + dialog error.
- `onAllSessionsStopped` di `main.dart` diganti engine.

**Acceptance criteria:**
- [ ] Heartbeat terus terkirim walau tak ada `DataCollectionScreen` terbuka, selama ada sesi.
- [ ] Service tak dimatikan saat 1 dari 2 sesi berhenti; dimatikan saat sesi terakhir berhenti.
- [ ] Gagal start service → sesi di-rollback, layar menampilkan dialog error seperti sekarang.

**Verification:**
- [ ] Unit (`tracking_engine_test.dart`, port fake): start A → service start 1×; `tick()` berulang → heartbeat terkirim tanpa layar; start B → tak start ulang; stop A → service tetap; stop B → service stop 1×.
- [ ] Manual: Start A → back ke daftar project → tunggu 60 dtk → jumlah titik A di panel terus naik; logcat tak ada "No heartbeat".

**Dependencies:** T1
**Files:** `lib/services/tracking/tracking_engine.dart` (baru), `lib/main.dart`, `lib/screens/data_collection/data_collection_screen.dart`, `lib/services/tracking/tracking_persistence_coordinator.dart`, `test/services/tracking/tracking_engine_test.dart`
**Scope:** M

#### Task 3: Restore & masuk ulang layar terhubung ke engine
**Description:**
- Sesi hasil restore dari SQLite dimuat sebagai `paused`.
- `_restoreTrackingState` memulihkan `_isPaused` dari sesi.
- Tombol Resume memanggil `manager.resume`, lalu engine menyala otomatis (0→1). Resume memakai alur izin yang sama dengan Start.

**Acceptance criteria:**
- [ ] Kill app saat 2 sesi → buka → kedua sesi tampil `paused` dengan titik utuh; REC tak berkedip untuk sesi paused.
- [ ] Resume salah satu → service menyala dan titik bertambah hanya untuk sesi itu.
- [ ] Masuk ulang ke project yang sedang recording menampilkan status Play/Pause yang benar.

**Verification:**
- [ ] Unit: `partitionRestorable` + restore menandai paused; engine start saat resume.
- [ ] Manual: skenario kill → buka → resume.

**Dependencies:** T2
**Files:** `lib/services/tracking/tracking_persistence_coordinator.dart`, `lib/screens/data_collection/data_collection_screen.dart`, `test/services/tracking/tracking_persistence_test.dart`
**Scope:** S

### Checkpoint A — Hotfix (tes di device sebelum lanjut)
- [ ] `flutter test test/services/tracking/ test/widgets/` hijau; `flutter analyze` 0 error di file berubah.
- [ ] Device (phone GPS): Start A → back → Start B → keduanya bertambah selama ≥2 menit dengan layar tertutup.
- [ ] Stop A → A berhenti bertambah, B lanjut; Stop B → notifikasi hilang, service mati.
- [ ] **Review dengan user** sebelum Phase 2.

### Phase 2 — Refactor: satu sumber kebenaran (I1–I5)

#### Task 4: Status sesi `recording | paused | pendingSave`
**Description:** Ganti `bool paused` dengan enum `SessionState`.
- `manager.finish(id)` → `pendingSave` (sebelumnya `pause`).
- `recordingCount` menggerakkan engine; cap = `recording + paused`.
- Panel menampilkan label "Belum disimpan" untuk `pendingSave`.
- Kolom DB `paused` memakai nilai 0/1/2.

**Acceptance criteria:**
- [ ] `ingest` hanya menambah ke sesi `recording`.
- [ ] Sesi `pendingSave` tak menghitung cap dan tak menahan service (Stop B saat A `pendingSave` → service mati).
- [ ] Round-trip DB 0/1/2 benar, dan data lama (0/1) tetap terbaca.

**Verification:**
- [ ] Unit: manager (cap, ingest per state), repository round-trip, engine (pendingSave tak menahan service).
- [ ] Widget: panel menampilkan label pendingSave.

**Dependencies:** T2
**Files:** `lib/services/tracking/tracking_session.dart`, `tracking_session_manager.dart`, `session_repository.dart`, `lib/widgets/tracking/active_tracking_panel.dart`, test terkait
**Scope:** M

#### Task 5: Sesi terikat provider + feed tunggal di engine
**Description:**
- `TrackingSession.provider` diisi saat Start (DB v5: kolom `provider`, `ALTER TABLE` di `_onUpgrade`).
- Engine berlangganan stream background phone **dan** `emlidLocationStream`, lalu memanggil `manager.ingest(point, source)`. Titik hanya masuk ke sesi dengan provider yang sama.
- Listener di `LocationServiceV2.startBackgroundTracking` tak lagi memanggil `addTrackingPoint`; engine yang jadi konsumen.

**Acceptance criteria:**
- [ ] Sesi Emlid terus bertambah walau layar ditutup (selama socket tersambung) dan tak pernah menerima titik phone.
- [ ] Sesi phone tak menerima titik Emlid.
- [ ] Ganti provider saat ada sesi → peringatan "N sesi memakai provider lain, sesi itu berhenti menerima titik".

**Verification:**
- [ ] Unit: ingest per provider; engine meneruskan dua stream fake ke sesi yang tepat.
- [ ] Unit: upgrade DB v4→v5 idempoten (baris lama → provider `phone`).
- [ ] Manual (bila ada Emlid): sesi RTK bertambah setelah back ke daftar project.

**Dependencies:** T4
**Files:** `tracking_session.dart`, `tracking_session_manager.dart`, `session_repository.dart`, `lib/services/database_service.dart`, `tracking_engine.dart`, `lib/services/location_service_v2.dart`
**Scope:** M

#### Task 6: DataCollectionScreen = view atas sesi
**Description:**
- Titik jalur dibaca dari getter `_draftPoints` = `sessionFor(id)?.points ?? _manualPoints`.
- Saat ada sesi, undo/clear/tambah-titik-tengah memanggil manajer (`removeLast`, `clear`, `appendManual`).
- Rebuild layar lewat listener manajer.
- Dihapus: append langsung di stream, `addTrackingPoint` dari layar, `_syncCollectedFromSession`, dan pemilihan stream berdasarkan `isActivelyTracking`. Marker memakai `engine.displayStream`.

**Acceptance criteria:**
- [ ] Buka project A saat A recording → jalur = titik sesi A persis (jumlah sama dengan panel), bertambah live.
- [ ] Undo, Clear, dan Add-center point tetap bekerja, baik dengan maupun tanpa sesi. Mode drawing (tap peta) tak berubah.
- [ ] Save dari layar menyimpan titik sesi lalu melepas sesi; jumlah titik = yang tampil.

**Verification:**
- [ ] Unit: `appendManual`/`removeLast`/`clear` di manajer (notify + persist).
- [ ] `flutter analyze` layar bersih.
- [ ] Manual: regresi 1-project (point/line/polygon, tracking & drawing) + multi-project.

**Dependencies:** T5
**Files:** `lib/screens/data_collection/data_collection_screen.dart`, `tracking_session_manager.dart`, `test/services/tracking/tracking_session_manager_test.dart`
**Scope:** M (satu file besar; bila membengkak, pecah 6a: sumber titik, 6b: stream/marker)

#### Task 7: Bersihkan state global + notifikasi tunggal
**Description:**
- Hapus `_isActivelyTracking`, `_activeTrackingPoints`, `start/pause/resume/stopActiveTracking`, dan `addTrackingPoint` dari `LocationServiceV2`. Sesi log GPS dipindah ke engine (0→1 / 1→0).
- Handler `detached` di `main.dart` dan layar memakai engine.
- Isolate berhenti menimpa notifikasi dengan "Accuracy | Points". Engine mengirim label `set_notification_text` ("Tracking N project aktif • ±X m") yang dipakai isolate.

**Acceptance criteria:**
- [ ] `grep isActivelyTracking|activeTrackingPoints|addTrackingPoint lib/` kosong.
- [ ] Notifikasi selalu menampilkan jumlah project yang benar selama tracking.
- [ ] App di-swipe (detached) → service berhenti (kebijakan tetap), sesi tersimpan sebagai paused.

**Verification:**
- [ ] Unit: teks notifikasi + engine mengirim label saat count berubah.
- [ ] `flutter analyze` 0 error di seluruh `lib/`.

**Dependencies:** T6
**Files:** `lib/services/location_service_v2.dart`, `lib/services/background/background_tracking_service.dart`, `tracking_engine.dart`, `lib/main.dart`, `data_collection_screen.dart`
**Scope:** M

#### Task 8: Skenario end-to-end (fake) + checklist device
**Description:** Satu test skenario lengkap dengan engine, manajer, dan port fake:
1. Start A → "layar ditutup" (tak ada konsumen UI) → tick > 15 dtk → A bertambah.
2. Start B → A & B bertambah.
3. Finish A → A `pendingSave` & berhenti; B lanjut.
4. Finish B → service stop.
5. Restore → paused.

Perbarui checklist manual di `tasks/todo.md`.

**Acceptance criteria:**
- [ ] Test skenario hijau dan gagal bila heartbeat dikembalikan ke layar (menjaga regresi C1).

**Verification:** `flutter test test/services/tracking/tracking_scenario_test.dart`
**Dependencies:** T7
**Files:** `test/services/tracking/tracking_scenario_test.dart`
**Scope:** S

### Phase 3 — UX pengelola tracking (permintaan user: lebih user friendly & interaktif)

#### Task 9: Panel "Tracking Aktif" interaktif
**Description:** Panel dan banner di daftar project menjadi pusat kendali semua sesi.
- Tiap kartu sesi menampilkan chip status (Merekam / Jeda / Belum disimpan), ikon provider, titik, jarak, durasi, dan waktu titik terakhir. Semuanya live.
- Aksi langsung: Jeda/Lanjutkan, Stop & Simpan (form atribut), Buang, dan Buka project.
- Banner menampilkan ringkasan per status ("2 merekam · 1 belum disimpan").

**Acceptance criteria:**
- [ ] Jeda/Lanjutkan dari panel mengubah status sesi dan engine (service ikut mati bila tak ada sesi merekam).
- [ ] Label status, durasi, dan jumlah titik ter-update live tanpa menutup panel.
- [ ] Banner merangkum per status; hilang bila tak ada sesi.

**Verification:**
- [ ] Widget test: toggle jeda/lanjut memanggil manajer; label status per state; teks ringkasan banner.
- [ ] Manual: kelola 3 sesi dari panel tanpa membuka layar project.

**Dependencies:** T4, T5
**Files:** `lib/widgets/tracking/active_tracking_panel.dart`, `test/widgets/active_tracking_panel_test.dart`
**Scope:** M

### Checkpoint B — Complete
- [ ] Semua test hijau; `flutter analyze` 0 error.
- [ ] Manual device (Android, lalu iOS): skenario 1-project (regresi), multi 2–3 project, layar tertutup ≥5 menit, kill/restore, Emlid (bila tersedia), cap, dan ganti provider.
- [ ] Siap review.

## Risks and Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Refactor layar 4.500 baris merusak mode manual/drawing | High | T6 dipisah dari hotfix; getter `_draftPoints` menjaga jalur manual; regresi manual point/line/polygon |
| Start service butuh izin/UI (dialog rationale) padahal engine non-UI | Med | Rationale tetap di layar sebelum `engine.ensureRunning()`; engine hanya menyalakan service |
| iOS menangguhkan socket Emlid di background | Med | Didokumentasikan; background RTK di iOS dianggap best-effort, sesi phone tetap andal |
| Migrasi DB v5 di perangkat lapangan | Med | `ALTER TABLE ... ADD COLUMN` idempoten + default `phone`, diuji |
| Uji timer tanpa `fake_async` (pubspec tak boleh disentuh) | Low | Timer factory diinjeksi; test memanggil `tick()` manual |
| App di-kill total → isolate tak bisa fan-out per sesi | Med | Di luar scope: kebijakan tetap "stop saat detached", sesi dipulihkan paused |

## Keputusan (default usulan dipakai — `/build auto` 2026-09-29)
1. Restore setelah kill → sesi **paused**, user menekan Lanjutkan.
2. `pendingSave` **tidak** dihitung cap.
3. Titik hanya masuk ke sesi dengan **provider yang sama**.
4. Semua phase dikerjakan berurutan; checkpoint device dilakukan user setelah build.
