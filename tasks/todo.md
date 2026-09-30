# TODO — Style per Feature + Select Feature dengan Tap Langsung (30 Sep 2026)

Spec: [SPEC.md](../SPEC.md) · Plan: [plan.md](plan.md) · Plan sebelumnya: `plan-sync-conflict.md` (arsip lokal)
Backend: `gis-backend` @ `dev1` · Mobile: `terestria` @ `main` · commit per task, tanpa push/deploy.
Baseline mobile: `flutter test` 641 lulus, `flutter analyze` 0 error dan 29 warning.

## Fase 1 — Kontrak & data
- [x] T1 (backend, gis-backend `d54d508`): `GeoData.style`, migrasi `0021` (manual), `clean_style`, serializer (tidak valid → dibuang, key tidak ada → dipertahankan, `null` → hapus), `to_mobile_json`. Test mock + test DB di CI.
- [x] T2: `feature_style.dart` (hex JSON, clamp, nilai awal dari Settings) + `GeoData.style`.
- [x] T3: DB v7 (kolom `style`, migrasi idempoten) + draft menyimpan style.
- [x] T4: push selalu mengirim `style`; pull (objek/`null`/tanpa key); "Use server" membawa style; `docs/sync-push-contract.md`.

### Checkpoint A
- [x] Semua test hijau (672); `analyze` sesuai baseline; belum ada perubahan yang terlihat user.

## Fase 2 — Lihat & atur style
- [x] T5: pembangun layer bersama (`project_feature_layers.dart`); style tampil di peta project dan navigasi; tanpa style = sama persis dengan sekarang.
- [x] T6: editor style bersama (`style_editor.dart`), diekstrak dari Layers tanpa perubahan perilaku.
- [x] T7: bagian "Style" di form "Survey data"; Save menyimpan style; "Save & next" membawa style; draft ikut.
- [x] T8: ubah/reset style di layar edit data (record jadi "belum sync").

### Checkpoint B
- [ ] Manual di HP: atur style saat koleksi dan saat edit, lihat di peta, sync, pull di HP kedua (backend T1 di dev).

## Fase 3 — Tap langsung
- [x] T9: hit-test murni (point/line/polygon, toleransi dp, urutan stabil).
- [ ] T10: daftar pilihan saat tap mengenai beberapa feature + helper `recordTitle()` bersama.
- [ ] T11: wiring `_onMapTap` (alat ukur → mode gambar → select) + hapus ikon info di peta project dan navigasi.

### Checkpoint C (selesai)
- [ ] Semua kriteria SPEC §9; test mobile/backend hijau; test DB di CI.
- [ ] Uji di HP:
  - upgrade v6 → v7;
  - sync ke HP kedua;
  - app lama tidak menghapus style;
  - edit dari dashboard tidak menghapus style;
  - ketepatan tap.
- [ ] Deploy backend T1 sebelum rilis app.
