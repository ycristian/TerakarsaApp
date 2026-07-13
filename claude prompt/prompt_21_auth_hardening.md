# Prompt 21 — Auth Hardening: PBKDF2, Rate Limit Login, JWT Config

## Konteks

Persiapan go-live. Password saat ini di-hash SHA256 hex tanpa salt dan dibandingkan di dalam SP `SIS_Login` (C# mengirim hash, SQL yang mencocokkan). Diganti dengan **PBKDF2** (salt per-user) — verifikasi WAJIB pindah ke C# karena hash tidak bisa dibandingkan langsung di SQL.

Keputusan migrasi: **reset semua password** (masih testing phase, tidak ada jalur verifikasi SHA256 legacy — hapus bersih). Setelah eksekusi, semua user lama tidak bisa login sampai password-nya di-set ulang.

Scope tambahan: rate limit endpoint auth + pengetatan konfigurasi JWT. Station token TIDAK disentuh.

## 1. PasswordHasher (C#)

Buat `TerakarsaApp.API/Services/PasswordHasher.cs` (static class atau service DI, pilih yang konsisten dengan pola repo):

- `Hash(string password)` → format simpan: `PBKDF2$<iterations>$<saltBase64>$<hashBase64>`
  - `Rfc2898DeriveBytes.Pbkdf2`, `HashAlgorithmName.SHA256`, iterasi **210000**, salt 16 byte (`RandomNumberGenerator`), hash 32 byte.
- `Verify(string password, string stored)`:
  - Parse format di atas (iterasi dibaca dari string simpanan — supaya iterasi bisa dinaikkan nanti tanpa merusak hash lama).
  - Bandingkan dengan `CryptographicOperations.FixedTimeEquals`.
  - Nilai simpanan yang TIDAK sesuai format (termasuk hex SHA256 lama atau marker reset) → return `false`, jangan throw.

## 2. Alur Login (AuthService + SP)

### SP baru: `SIS_User_GetByUsername` (`sql/sp_User_GetByUsername.sql`)
- Parameter `@Username`. Kembalikan: `Id, Username, Password, FullName, Role, IsActive` untuk user hidup (ikuti filter yang dipakai `SIS_Login` sekarang). Tanpa parameter password — pencocokan bukan lagi urusan SQL.

### AuthService
- Hapus method `HashPassword` (SHA256) — tidak boleh ada sisa pemakaian SHA256 untuk password di seluruh solution.
- `LoginAsync`: panggil `SIS_User_GetByUsername`, lalu `PasswordHasher.Verify` di C#. User tidak ditemukan, nonaktif, ATAU password salah → response error yang SAMA PERSIS (mis. "Username atau password salah.") — jangan bocorkan yang mana yang salah.
- Alur refresh token / rotasi / revoke TIDAK berubah.

### SP lama `SIS_Login`
- Jangan drop. Tandai deprecated di komentar atas file `sql/sp_Login.sql` ("digantikan SIS_User_GetByUsername + verifikasi PBKDF2 di C#, Prompt 21"). Tidak ada lagi kode C# yang memanggilnya.

## 3. Semua Jalur Set Password

Telusuri semua tempat password di-set (buat user baru, ubah password oleh admin, ganti password sendiri bila ada — cek `UserService`, `SIS_User_Manage`, dan controller terkait):
- Hashing pindah ke C# via `PasswordHasher.Hash` sebelum dikirim ke SP. SP hanya menyimpan string apa adanya.
- Kalau ada SP yang selama ini menerima password polos lalu hash di SQL — tidak boleh lagi; SP menerima hash jadi.
- Pastikan panjang kolom cukup (bagian 5) sebelum menyimpan format baru.

## 4. Tool Reset Password Admin

PBKDF2 tidak bisa dihitung di T-SQL, jadi hash bootstrap admin dibuat lewat tool kecil:

- Buat project console minimal `tools/PasswordHashTool/` (satu `Program.cs`): baca password dari argumen, cetak hash PBKDF2 (pakai `PasswordHasher` yang sama — reference project API atau duplikasi minimal 1 method dengan komentar sumber).
- Tool ini TIDAK ikut publish/deploy — hanya utilitas dev. Tambahkan ke solution bila perlu untuk build, atau biarkan standalone dengan instruksi `dotnet run`.

## 5. Skema & Script SQL

### a. Edit `sql/create_tables_tmos_final.sql`
- Kolom `Users.Password` → `varchar(500)` (format PBKDF2 lebih panjang dari hex 64). Tambah komentar format simpanan.

### b. Buat `sql/alter_21_password_pbkdf2.sql` (dijalankan manual, idempotent)
```sql
-- Prompt 21: pelebaran kolom password untuk format PBKDF2$iter$salt$hash
ALTER TABLE Users ALTER COLUMN Password varchar(500) NOT NULL;
GO
```

### c. Buat `sql/reset_passwords_prompt21.sql` (dijalankan manual)
```sql
-- Prompt 21: reset semua password (migrasi SHA256 -> PBKDF2, tanpa jalur legacy).
-- 'RESET!' bukan format PBKDF2 valid -> PasswordHasher.Verify selalu false -> tidak bisa login.
UPDATE Users SET Password = 'RESET!';
GO

-- Ganti <HASH_ADMIN> dengan hasil: dotnet run --project tools/PasswordHashTool -- <password_baru>
UPDATE Users SET Password = '<HASH_ADMIN>' WHERE Username = 'admin';
GO
```
Sesuaikan `'admin'` dengan username admin aktual di repo/seed. User `station_system` sengaja ikut ter-reset — IsActive = 0, tidak pernah login.

## 6. Rate Limit Endpoint Auth

Di `Program.cs`:
- `AddRateLimiter` dengan policy bernama `"auth"`: fixed window per IP (partisi `RemoteIpAddress`), **5 request / menit**, tanpa antrian (QueueLimit 0).
- `OnRejected`: status 429 + body teks Indonesia, mis. "Terlalu banyak percobaan. Coba lagi sebentar lagi."
- `app.UseRateLimiter()` di posisi middleware yang benar.
- Terapkan HANYA ke endpoint login dan refresh (`[EnableRateLimiting("auth")]` di action/controller terkait). Endpoint lain, termasuk semua endpoint station, TIDAK dibatasi.
- Client: pastikan pesan 429 tampil wajar di halaman login (pakai penanganan error response yang sudah ada; kalau body 429 tidak terbaca, tampilkan pesan fallback yang sama).

## 7. Konfigurasi JWT

Di `Program.cs`:
- Validasi startup: `JwtSettings:Key` minimal **32 karakter** — kalau kurang, `throw` dengan pesan jelas saat aplikasi start (fail fast, jangan diam-diam jalan).
- `ClockSkew = TimeSpan.FromMinutes(1)` eksplisit di `TokenValidationParameters`.
- Konfirmasi (tanpa mengubah mekanisme): key bisa di-override environment variable `JwtSettings__Key` (perilaku bawaan ASP.NET config) — tambahkan komentar di `Program.cs` dan catatan di `appsettings.json` bahwa untuk produksi/Azure key WAJIB dari App Settings/env var, bukan dari file. Kalau key di `appsettings.json` dev saat ini < 32 karakter, ganti dengan key dev baru yang memenuhi syarat.

## Aturan tetap berlaku

Soft delete, filter `deleted_at IS NULL`, prefix SP `SIS_`, UI bahasa Indonesia, script SQL manual di folder `sql/` (JANGAN auto-execute ke DB).

## Yang TIDAK boleh dilakukan

- Jangan pakai ASP.NET Core Identity — tetap JWT manual seperti sekarang.
- Jangan buat jalur verifikasi SHA256 legacy / rehash-on-login — keputusan: reset bersih.
- Jangan sentuh mekanisme station token (`X-Station-Token`) dan endpoint station.
- Jangan ubah struktur/rotasi refresh token — sudah benar.
- Jangan drop SP `SIS_Login` — cukup deprecated.
- Jangan simpan password polos di mana pun (log, response, DB).

## Verifikasi

1. `dotnet build` sukses (termasuk tools/PasswordHashTool bila masuk solution).
2. Cari sisa `SHA256` terkait password di solution — harus nol (SHA256 untuk keperluan lain non-password, bila ada, boleh).
3. Uji manual setelah jalankan `alter_21` + `reset_passwords_prompt21` (dengan hash admin dari tool):
   - Login admin dengan password baru → sukses; password lama/user lain (marker RESET!) → gagal dengan pesan generik.
   - Buat user baru dari UI → login user baru sukses (hash tersimpan format `PBKDF2$...`).
   - Ubah password user → login dengan password baru sukses, lama gagal.
   - Login salah 6x berturut dalam 1 menit → percobaan ke-6 kena 429, pesan tampil di halaman login.
   - Refresh token tetap bekerja normal setelah login.
   - Set `JwtSettings:Key` < 32 karakter → aplikasi gagal start dengan pesan jelas (lalu kembalikan).
4. Di akhir: daftar file yang diubah/dibuat + daftar script SQL yang harus dijalankan manual + contoh perintah PasswordHashTool.
