# Prompt 84 — Station: token perangkat hanya dihapus kalau server menjawab 401

Perbaikan kecil **khusus client**, dipasang SENDIRI lebih dulu sebelum Prompt 85/86.
Tujuannya: deploy/restart API saat stasiun sedang dipakai tidak boleh membuat perangkat
ter-logout.

**Prasyarat:** `StationDevice.razor` dan `StationDeviceApiService.cs` sedang diubah oleh
pekerjaan lain yang belum di-commit (`alter_87` allow_all_divisions). Kerjakan di atas
keadaan file terkini tanpa mengubah logika divisi itu. Catatan deploy: kalau perubahan
client `alter_87` ikut ter-build, publish client prompt ini baru aman "sendiri" setelah
SQL + API `alter_87` terpasang — laporkan di akhir apakah build client ini bergantung pada
API `alter_87`.

## 0. Masalah

- `StationDeviceApiService.GetMeAsync`
  (`TerakarsaApp.Client/Services/StationDeviceApiService.cs`) mengembalikan `null` untuk
  **semua** respons gagal (`!IsSuccessStatusCode`), bukan hanya 401.
- `StationDevice.razor` `OnInitializedAsync` menganggap `null` = token tidak berlaku lalu
  `localStorage.removeItem("stationToken")` + pesan "Token perangkat sudah tidak berlaku".
- Akibatnya stasiun yang me-reload halaman tepat saat API restart (IIS 503 /
  `app_offline.htm`) atau SP sempat error (500) kehilangan token yang sebenarnya masih sah
  di DB → harus minta kode pairing baru ke admin.
- Kalau jaringan putus total, `GetAsync` melempar exception dan `OnInitializedAsync` gagal
  (halaman error). Token tidak hilang, tapi layar rusak.

Polling dan pemanggilan API lain TIDAK menghapus token (penghapusan hanya di init, setelah
klaim, dan `ReleaseToken`) — jadi cakupan perbaikan cukup dua titik di bawah.

## 1. `StationDeviceApiService.GetMeAsync`

Ubah supaya membedakan tiga hasil, mis. tuple
`(StationMeDto? Station, bool Unauthorized)` atau enum kecil — pilih yang paling ringkas:

- sukses → data stasiun;
- **401** → `Unauthorized = true`;
- gagal lain (status non-sukses selain 401, `HttpRequestException`,
  `TaskCanceledException`) → `Station = null`, `Unauthorized = false`. Exception ditangkap
  di sini, tidak dilempar ke halaman.

Pemanggil `GetMeAsync` lain (kalau ada) disesuaikan tanpa mengubah perilakunya.

## 2. `StationDevice.razor`

Dua titik yang sekarang menghapus token setelah `GetMeAsync` gagal:

1. `OnInitializedAsync`, cabang "sudah punya token" (pesan "Token perangkat sudah tidak
   berlaku...").
2. `ClaimAsync`, setelah klaim sukses lalu `GetMeAsync` gagal (pesan "Gagal mengaktifkan
   perangkat...").

Aturan baru di keduanya:

- `Unauthorized` → perilaku lama (hapus token + pesan yang sama).
- Gagal lain → **token tetap disimpan**. Tampilkan layar/kartu
  `Server tidak terjangkau. Mencoba lagi...` dengan tombol `Coba sekarang`, dan coba
  `GetMeAsync` lagi otomatis tiap 5 detik sampai sukses (lanjut normal ke
  `LoadOperatorSessionAsync`) atau 401 (perilaku lama). Timer dihentikan saat halaman
  di-dispose — ikuti pola `pollTimer`/`StopPolling` yang sudah ada.

## 3. Yang TIDAK boleh dilakukan

- Mengubah API, SQL, atau `StationTokenHandler`.
- Mengubah alur scan `/station/{kode}` saat sudah punya token (logout-lalu-klaim) — itu
  bagian Prompt 85.
- Menyentuh polling, tab, atau pemanggilan API stasiun lain.

## 4. Verifikasi

- `dotnet build TerakarsaApp.slnx -v q` lolos.
- Telusuri ulang: satu-satunya jalur `removeItem(TokenKey)` setelah `GetMeAsync` hanya
  terjadi pada 401.
- Tidak ada script SQL.

## 5. Deploy

Publish `TerakarsaApp.Client`, salin file statis ke IIS. API tidak restart → aman
dipasang saat stasiun sedang dipakai. Halaman yang sedang terbuka tetap memakai versi lama
sampai di-reload.
