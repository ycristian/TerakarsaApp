# Prompt 20 — Pairing Station Sekali Pakai & Link Autologin

> Independen dari Prompt 18/19; menyentuh area station saja.

## Konteks

Saat ini `station_token` bersifat permanen dan disalin manual ke perangkat (localStorage, header `X-Station-Token`). Kelemahan: token yang sama bisa ditempel di banyak perangkat, dan siapa pun yang pernah melihat tokennya bisa memakainya selamanya.

Desain baru — **kode pairing sekali pakai + link autologin**:
1. Admin di halaman Kelola Stasiun klik "Buat Kode Pairing" → server generate kode **5 karakter acak** (huruf besar/kecil + angka, hindari karakter membingungkan `0/O/l/1/I`), berlaku **15 menit**, **sekali pakai**.
2. UI menampilkan kode DAN **link siap salin**: `{base URL client}/station/{kode}` (mis. `https://.../station/AxS3q`).
3. Perangkat membuka link → halaman station otomatis menukar (claim) kode ke API:
   - Kode valid & belum kedaluwarsa → server **generate `station_token` BARU** (rotate; token lama mati → perangkat lama tertendang, satu perangkat aktif per station), hanguskan kode pairing, kembalikan token baru.
   - Perangkat simpan token ke localStorage (mekanisme `TokenKey` yang sudah ada) → langsung masuk kiosk. Link/kode tidak bisa dipakai lagi.
4. Kode juga bisa diketik manual di layar aktivasi perangkat (pengganti input "tempel token" sekarang — token mentah tidak pernah lagi dilihat/diketik manusia).
5. **Logout perangkat** = panggil endpoint unpair (hanguskan token di server, pakai `X-Station-Token`) lalu hapus localStorage → masuk lagi harus minta kode pairing baru ke admin.

## 1. Skema

### `sql/alter_20_station_pairing.sql` (manual, idempotent) + update `create_tables_tmos_final.sql`
Tambah di `stations`:
```sql
 pairing_code varchar(10) null,             -- kode pairing aktif; NULL = tidak ada
 pairing_code_expires_at datetime2 null,
 paired_at datetime2 null,                  -- kapan terakhir perangkat berhasil klaim
```
Index unik filtered: `UX_stations_pairing_code ON stations(pairing_code) WHERE pairing_code IS NOT NULL AND deleted_at IS NULL`.

## 2. Stored Procedures

### `sql/sp_Station_Manage.sql` — action baru di `SIS_Station_Manage` (atau SP kecil terpisah bila lebih rapi, ikuti pola file):
1. **`GENERATE_PAIRING`** (`@Id`, `@PairingCode`, `@UserId`): station harus hidup & aktif. Set `pairing_code = @PairingCode`, `pairing_code_expires_at = DATEADD(MINUTE, 15, SYSDATETIME())`. Kode digenerate di API (5 karakter, charset tanpa `0 O l 1 I`); bila bentrok unique index, API retry generate. Generate ulang menimpa kode lama (kode lama otomatis hangus).
2. **`CLAIM_PAIRING`** (`@PairingCode`, `@NewToken`): cari station hidup & aktif dengan kode itu dan `pairing_code_expires_at > SYSDATETIME()`. Tidak ketemu/kedaluwarsa → RAISERROR "Kode pairing tidak valid atau sudah kedaluwarsa." Ketemu → `station_token = @NewToken` (digenerate API, GUID tanpa strip seperti sekarang), `pairing_code = NULL`, `pairing_code_expires_at = NULL`, `paired_at = SYSDATETIME()`; kembalikan data station + token baru. Seluruhnya atomik.
3. **`UNPAIR`** (`@Id` dari token perangkat): `station_token` diganti GUID baru (token lama mati), `paired_at = NULL`.

Endpoint `RegenerateToken` lama: alihkan maknanya menjadi "putuskan perangkat" (sama dengan UNPAIR dari sisi admin) — token baru TIDAK ditampilkan ke admin lagi.

### `sql/sp_Station_Select.sql`
`SIS_Station_GetAll`/`GetById`: tambah kolom status pairing untuk admin — `paired_at`, dan indikator kode aktif (`pairing_code_expires_at` bila masih berlaku; **jangan** kembalikan `station_token` bila saat ini dikembalikan).

## 3. API

### `StationController.cs` (JWT, admin)
- `POST {id}/pairing-code`: generate kode (retry bila unik bentrok) → simpan via SP → response `{ code, expiresAt, link }`; `link` dirakit dari base URL client (pakai `PublicBaseUrl` yang sudah ada di konfigurasi) + `/station/` + kode.
- Endpoint `regenerate-token` → ganti jadi `POST {id}/unpair` (putuskan perangkat).

### `StationDeviceController.cs` / endpoint claim (ANONIM — tanpa JWT & tanpa station token)
- `POST api/station-device/claim`, body `{ code }` → validasi via SP CLAIM_PAIRING → response station info + token baru. Beri komentar keamanan: kode 5 karakter + kedaluwarsa 15 menit + sekali pakai; tolak input yang tidak sesuai pola (panjang/charset) sebelum ke DB.
- `POST api/station-device/logout` (pakai `X-Station-Token`) → UNPAIR.
- `StationService.cs` / `StationDeviceApiService.cs` / model Shared menyesuaikan.

## 4. Client

### `StationDevice.razor`
- Route tambahan: `@page "/station/{PairingCode}"` di samping `@page "/station"`. Bila parameter terisi dan perangkat belum punya token → otomatis claim; sukses → simpan token, bersihkan URL (navigasi ke `/station` tanpa reload), masuk kiosk. Gagal → tampilkan pesan + form input kode.
- Layar aktivasi: input "tempel token" diganti input **kode pairing** (5 karakter) + tombol Aktifkan → claim endpoint yang sama.
- Bila perangkat sudah punya token dan link pairing dibuka → abaikan kode, langsung masuk kiosk (atau tampil konfirmasi "Perangkat sudah aktif").
- Tombol **Keluar/Logout** di kiosk (letak wajar, konfirmasi dulu): panggil endpoint logout → hapus `TokenKey` (+ operator keys) → kembali ke layar aktivasi.
- Token yang tersimpan jadi tidak valid (mis. admin unpair / perangkat lain klaim) → perilaku yang ada sekarang (hapus token, kembali ke layar aktivasi) dipertahankan; pastikan pesannya menyebut "minta kode pairing baru ke admin".

### `Station.razor` (Kelola Stasiun, admin)
- Ganti tampilan/salin token dengan: tombol **"Buat Kode Pairing"** per station → modal menampilkan kode besar + link + tombol **Salin Link** + masa berlaku. Kolom status: "Terhubung sejak ..." / "Belum terhubung" / "Kode aktif s.d. ...".
- Tombol **"Putuskan Perangkat"** (unpair) dengan konfirmasi.

## Aturan tetap berlaku
Soft delete, prefix `SIS_`, pola `@Action`, UI Indonesia, JS interop localStorage (bukan Blazored), pola modal yang sudah ada.

## Yang TIDAK boleh dilakukan
- Jangan tampilkan `station_token` di UI admin atau response GetAll/GetById.
- Jangan simpan kode pairing di client selain untuk sekali claim.
- Jangan ubah mekanisme header `X-Station-Token` dan `RequireStationTokenAttribute` untuk request harian.
- Jangan buat tabel perangkat terpisah — tetap satu perangkat aktif per station lewat rotasi token.

## Verifikasi
1. `dotnet build` sukses.
2. Skenario manual (setelah `alter_20`):
   - Buat kode pairing → buka link di perangkat → langsung masuk kiosk; buka link yang sama di perangkat kedua → ditolak (kode sudah terpakai).
   - Perangkat A aktif, buat kode baru dan klaim di perangkat B → B masuk, A tertendang saat request berikutnya (kembali ke layar aktivasi).
   - Kode dibiarkan >15 menit → claim ditolak.
   - Logout di perangkat → kembali ke layar aktivasi; token lama tidak bisa dipakai lagi.
   - Admin "Putuskan Perangkat" → perangkat tertendang.
3. Di akhir: daftar file diubah/dibuat + script SQL manual.
