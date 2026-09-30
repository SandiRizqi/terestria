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
