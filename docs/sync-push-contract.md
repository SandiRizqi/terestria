# API Contract — Push GeoData (mobile → server)

Endpoint: `POST /mobile/geodata/` (upsert satu record; `bulk_sync` mengikuti aturan yang sama
per item). Implementasi server: gis-backend `mobile/views.py` (`GeoDataViewSet.create`).
Pasangan kontrak pull: [sync-delta-api-contract.md](sync-delta-api-contract.md).

## 1. Request

Field lama tetap (`id`, `project_id`, `form_data`, `points`, `created_at`, `updated_at`, …), ditambah:

| Field | Wajib | Keterangan |
|---|---|---|
| `base_updated_at` | tidak | `updated_at` **server** terakhir yang dilihat app untuk record ini (dari pull atau respons push), ISO8601 UTC. Kosong/tidak ada → tanpa cek konflik (perilaku lama). |
| `force` | tidak | `true` = user memilih **Keep mine**: timpa versi server walau berubah. |
| `style` | tidak (app ≥ fitur style **selalu** mengirim) | Style tampilan feature (lihat §4): objek, atau `null` = ikut default aplikasi (server menghapus style tersimpan). Key **tidak ada** → style tersimpan dipertahankan. |

## 2. Response

| Status | Kapan | Body |
|---|---|---|
| `201` / `200` | Tersimpan (baru / diperbarui) | `{"success": true, "message": ..., "data": <record>}` — `data.updatedAt` = versi server baru; app menyimpannya sebagai `base_updated_at` berikutnya. |
| `403` | Project `is_active = false` | `{"success": false, "error_code": "project_inactive", "message": "Project \"X\" is not accepting data right now (inactive)."}` |
| `409` | Record berubah di server setelah `base_updated_at` (dan bukan `force`) | `{"success": false, "error_code": "conflict", "message": ..., "data": <versi server, URL foto ber-tanda-tangan>}` |
| `4xx/5xx` lain | Error lain | `{"success": false, "message": ..., "error": ...}` |

App menampilkan `message` untuk `error_code` yang dikenali (bukan pesan generik per status).

## 3. Aturan

1. Versi = `updated_at` yang diisi **jam server** oleh serializer pada setiap simpan — bebas
   selisih jam HP. Konflik bila `server.updated_at > base_updated_at` (presisi mikrodetik).
2. Backward-compatible: app versi lama tak mengirim `base_updated_at` → tak pernah 409.
3. Project nonaktif hanya menolak **data** (geodata); sinkron metadata project tidak terpengaruh.
4. `bulk_sync`: item konflik / project nonaktif masuk `errors[]` dengan `error_code` yang sama
   (konflik juga membawa `data`); item lain tetap diproses.
5. Verifikasi manual (dashboard) hanya di-reset bila **isi** record berubah: isian form non-foto
   atau koordinat titik. Push yang hanya mengubah style atau foto, atau mengirim ulang data yang
   sama, mempertahankan verifikasi (gis-backend `validation.ingest_content_changed`).

## 4. Style per feature (`style`)

Tampilan satu record di peta (sama dengan editor Layers). Server: kolom `GeoData.style`
(gis-backend migrasi `0021`, validasi `mobile/validation.clean_style`). Mobile:
`lib/models/feature_style.dart`.

```json
"style": {
  "fillColor": "#FF9800",
  "fillOpacity": 0.3,
  "strokeColor": "#E65100",
  "strokeWidth": 2.0,
  "pointSize": 12.0
}
```

- Tepat 5 key. Warna `#RRGGBB` (opacity terpisah); rentang: `fillOpacity` 0.05–1,
  `strokeWidth` 0.5–10, `pointSize` 4–20 (mobile men-clamp sebelum kirim).
- Pemakaian per geometri: point = `fillColor`+`fillOpacity`, `pointSize`; line =
  `strokeColor`+`fillOpacity`, `strokeWidth`; polygon = isi `fillColor`+`fillOpacity`, garis
  tepi `strokeColor`, `strokeWidth`.

| Kejadian | Aturan |
|---|---|
| Push dengan objek valid | Disimpan (hex dinormalisasi huruf besar). |
| Push dengan `null` | Style dihapus → ikut default aplikasi. |
| Push **tanpa** key `style` (app lama, edit dari web dashboard) | Style tersimpan **dipertahankan**. |
| Push dengan style tidak valid | Key dibuang: record **tetap diterima**, style tersimpan tidak tertimpa. |
| Pull / respons 409 | `to_mobile_json` selalu menyertakan `style` (null bila tidak ada). |
| Pull dari backend lama (key tidak ada) | Mobile mempertahankan style lokal; `null` → dihapus; objek → dipakai. |
