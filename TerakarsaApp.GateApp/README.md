# TerakarsaApp.GateApp — Aplikasi Gate Satpam (Absensi RFID)

Aplikasi desktop Windows (WPF + BlazorWebView) untuk tablet di meja satpam. Dipakai mencatat
pengambilan dan pengembalian kartu RFID pegawai; absensi diturunkan dari tap itu.

**Kartu tidak pernah dibawa pulang** — dititip di rak gate, diambil tiap pagi, dikembalikan tiap
sore. Karena itu status kartu = status orang, dan **tidak ada tombol MASUK/PULANG** di layar.
Semua keputusan masuk/pulang ada di `SIS_Gate_Tap` di server. Aplikasi ini hanya mengantre tap
dan menampilkan hasilnya.

Dari kartu hanya **UID yang dibaca**. Tidak ada data apa pun yang ditulis ke kartu.

---

## 1. Syarat perangkat

| Hal | Keterangan |
|---|---|
| Perangkat | Tablet Windows 2-in-1 10 inci, layar sentuh, di dudukan meja satpam |
| Resolusi | 1920 × 1280 fisik, **skala tampilan Windows 150%** → UI dirancang untuk 1280 × 853 CSS px |
| Reader | USB RFID 13,56 MHz **keyboard emulation** (plug & play, tanpa driver/SDK). Output 10 digit desimal + Enter |
| Kartu | Mifare S50 1K, PVC 0,8 mm, 4-byte UID |
| Runtime | **Microsoft Edge WebView2 Runtime** wajib terpasang (lihat §6) |
| Listrik | Tablet **sebaiknya selalu tercolok**. Baterai hanya cadangan saat padam |
| Jam | Jam tablet **harus benar** — lihat §5, ini syarat paling mudah dilupakan |

Reader dicolok lewat dock/hub USB bersama charger. Tidak ada setelan apa pun yang perlu diubah di
reader: Windows melihatnya sebagai keyboard, dan aplikasi cukup menjaga satu input tetap di-fokus.

---

## 2. Setel skala tampilan Windows ke 150%

Seluruh ukuran teks dan tombol dirancang untuk skala 150%. Pada 100% semuanya akan tampak kecil
dan tombol jadi sulit disentuh dengan jari.

1. Klik kanan desktop → **Display settings** (Pengaturan tampilan).
2. Bagian **Scale & layout** → **Scale** → pilih **150%**.
3. Keluar dan masuk lagi (sign out / sign in) kalau Windows memintanya.

Aplikasi sudah mendeklarasikan DPI awareness `PerMonitorV2` (`app.manifest`), jadi WebView2 ikut
diskalakan Windows dengan benar tanpa setelan tambahan.

**Keyboard sentuh:** layar "Ubah data karyawan" butuh mengetik nama/no. telepon. Nyalakan keyboard
sentuh Windows: Settings → Time & language → Typing → Touch keyboard → aktifkan
*"Show the touch keyboard when there's no keyboard attached"*.

---

## 3. appsettings.json

Ada di folder exe, dibaca saat aplikasi start (bukan reload otomatis — restart setelah diubah).

```json
{
  "GateService": {
    "ApiBaseUrl": "http://192.168.8.233:5281/",
    "ApiKey": "harus sama persis dengan GateService:ApiKey di appsettings API",
    "GateCode": "GATE-UTAMA",
    "CardSyncSeconds": 300,
    "QueueFlushSeconds": 10,
    "TapCooldownSeconds": 30,
    "ClockDriftWarningSeconds": 120,
    "MenuIdleTimeoutSeconds": 60,
    "ResultScreenSeconds": 3,
    "SoundVolumePercent": 80
  }
}
```

| Kunci | Arti |
|---|---|
| `ApiBaseUrl` | Alamat API TMOS, **dengan garis miring di akhir** |
| `ApiKey` | Dikirim sebagai header `X-Gate-Api-Key`. **Harus sama persis** dengan `GateService:ApiKey` di `TerakarsaApp.API/appsettings.json`, kalau tidak semua panggilan dijawab 401 |
| `GateCode` | Tersimpan di `gate_taps.gate_code` dan tampil sebagai judul layar. Ganti kalau tablet dipindah ke pintu lain — tidak ada yang hardcode di kode |
| `CardSyncSeconds` | Selang tarik master kartu & karyawan |
| `QueueFlushSeconds` | Selang kirim antrian tap |
| `TapCooldownSeconds` | Tap kartu yang sama dalam rentang ini dijawab DUPLIKAT. Server mengecek ulang nilai yang sama (30 detik) — jangan dinaikkan di sini tanpa mengubah SP |
| `ClockDriftWarningSeconds` | Selisih jam tablet vs server yang memunculkan peringatan |
| `MenuIdleTimeoutSeconds` | Menu satpam tertutup sendiri setelah diam sekian detik |
| `ResultScreenSeconds` | Lama layar hasil tampil sebelum kembali ke layar tunggu |
| `SoundVolumePercent` | Volume awal bunyi (0–100). Bisa diubah satpam di menu, tapi tidak tersimpan — restart kembali ke nilai ini |

### Ganti GateCode

Cukup ubah `GateService:GateCode` lalu restart aplikasi. Tidak ada yang perlu didaftarkan di
database — `gate_code` disimpan apa adanya di `gate_taps` sebagai jejak pintu mana yang memproses
tap itu.

---

## 4. gate.db (cache lokal)

File SQLite di folder exe. Tiga tabel:

| Tabel | Isi | Boleh hilang? |
|---|---|---|
| `cards` | Cache kartu aktif + nama/jabatan/resource | **Ya** — ditimpa penuh tiap sync berhasil |
| `employees` | Cache karyawan aktif | **Ya** — sama |
| `tap_queue` | Tap yang belum terkirim ke server | **TIDAK** — baris yang hilang di sini = absensi orang yang hilang |

**`gate.db` boleh dihapus kapan saja** — asal **antriannya kosong** (lihat Menu → Status &
sinkronisasi, angka "Tap menunggu dikirim" harus 0). Setelah dihapus, aplikasi membuatnya ulang dan
sync berikutnya mengisi cache. Kalau file-nya korup, aplikasi menghapus dan membuat ulang sendiri.

Baris yang sudah terkirim dibersihkan otomatis setelah 7 hari.

---

## 5. Jam tablet

`check_in_at` dan `check_out_at` memakai **jam tap dari tablet**, bukan jam server — itulah yang
membuat tap saat jaringan mati tetap tercatat di jam yang benar. Konsekuensinya: **jam tablet yang
salah merusak semua jam absensi.**

Nyalakan sinkronisasi waktu Windows:

1. Settings → Time & language → Date & time.
2. **Set time automatically** → On.
3. **Time zone** → (UTC+07:00) Bangkok, Hanoi, Jakarta.
4. Tekan **Sync now** sekali untuk memastikan.

Aplikasi membandingkan jam tablet dengan jam server tiap sync. Selisih di atas
`ClockDriftWarningSeconds` memunculkan banner kuning di layar tunggu dan angka selisihnya di
Menu → Status & sinkronisasi.

---

## 6. WebView2 Runtime

UI dirender WebView2. Kalau belum terpasang, aplikasi gagal menampilkan apa pun (window kosong).

- Windows 11 dan Windows 10 yang ter-update umumnya **sudah** memilikinya.
- Kalau belum: pasang **Microsoft Edge WebView2 Runtime (Evergreen Bootstrapper)** dari halaman
  resmi Microsoft "Microsoft Edge WebView2".
- Cara cek: Settings → Apps → Installed apps, cari "Microsoft Edge WebView2 Runtime".

---

## 7. Pasang auto-start

Aplikasi harus hidup sendiri setelah tablet menyala atau setelah listrik padam.

**Cara paling sederhana (folder Startup):**

1. Tekan `Win + R`, ketik `shell:startup`, Enter.
2. Buat shortcut ke `TerakarsaApp.GateApp.exe` di folder yang terbuka.

**Supaya tidak perlu login manual setelah listrik padam**, aktifkan juga auto sign-in:
Settings → Accounts → Sign-in options → *"Use my sign-in info to automatically finish setting up
after an update or restart"*.

Aplikasi berjalan maximized, tanpa title bar, dan `Topmost` — tidak bisa di-minimize atau ditutup
dari luar. **Satu-satunya jalan keluar** ada di Menu satpam → "Keluar aplikasi", dan menu itu
hanya terbuka dengan tap kartu ber-jabatan `is_gate_operator = 1`.

---

## 8. Suara

Bunyi **berbeda per hasil** adalah lapis verifikasi utama, bukan pelengkap: layar menghadap satpam
saja (karyawan tidak melihatnya), dan satpam sering menunduk mencari kartu di rak.

| Hasil | Bunyi |
|---|---|
| CHECK_IN | bip pendek 1× |
| CHECK_OUT | bip pendek 2× |
| DUPLIKAT / tersimpan offline | bip pelan 1× |
| Ditolak / perlu konfirmasi | bip panjang rendah |

Bunyi **disintesis aplikasi** (gelombang dibuat di memori lalu diputar `System.Media.SoundPlayer`),
supaya volume bisa diatur dari menu satpam — `SoundPlayer` sendiri tidak punya properti volume.

**Override dengan file WAV:** taruh file berikut di folder exe dan file itu yang akan dipakai:

```
check_in.wav    check_out.wav    duplikat.wav    reject.wav
```

File WAV diputar apa adanya, jadi **pengatur volume di menu tidak berlaku** untuk file itu (atur
volume Windows). Tidak ada file = tetap jalan dengan bunyi sintesis; aplikasi tidak pernah bisu
karena file hilang.

**Speaker:** speaker bawaan tablet 10 inci kecil dan mudah tenggelam di keramaian pagi. Siapkan
speaker USB atau 3,5 mm kecil di meja satpam. Dari sisi aplikasi tidak ada yang berubah — Windows
sudah mengarahkan suara ke perangkat output yang dipilih. Pakai Menu → Status & sinkronisasi →
tombol **tes bunyi** untuk memastikan speaker hidup tanpa menunggu ada yang tap.

---

## 9. Yang butuh online dan yang tidak

| Aksi | Offline? |
|---|---|
| Tap kartu | **Bisa.** Masuk `tap_queue`, dikirim saat jaringan kembali, **jam yang tercatat tetap jam tap** |
| Layar hasil menampilkan nama & resource | Bisa, dari cache — tapi **tidak** menyebut masuk/pulang (itu keputusan server) |
| Buka menu satpam | Bisa (jabatan kartu ada di cache) |
| Daftar "Belum ambil / Belum kembalikan kartu" | **Tidak** — status sesi menit ini tidak boleh ditebak dari cache |
| Daftar kartu baru | **Tidak** — UID kembar harus dicek ke server. Ditolak dengan pesan jelas, tidak diantrekan |
| Ubah data karyawan | **Tidak** — jejaknya harus langsung tercatat beserta nama satpam |
| Konfirmasi sesi > 14 jam | **Tidak** — layar konfirmasi butuh info sesi dari server |

Saat offline, tap yang masuk antrian dan kebetulan bersesi > 14 jam diputuskan server sendiri
sebagai ANOMALI + `BELUM_CHECKOUT` saat antrian dikirim, lalu dikoreksi admin di halaman
**Absensi → Koreksi Absensi**.

---

## 10. Masalah yang sering muncul

| Gejala | Penyebab paling umum |
|---|---|
| Window kosong / putih | WebView2 Runtime belum terpasang (§6) |
| Semua panggilan gagal, indikator selalu kuning | `ApiKey` tidak sama dengan di API, atau `ApiBaseUrl` salah/tanpa garis miring akhir |
| Tap tidak terbaca sama sekali | Reader tidak dikenali sebagai keyboard — coba tap di Notepad, harus muncul 10 digit + Enter |
| Tap terbaca di Notepad tapi tidak di aplikasi | Ada window lain di atas yang mengambil fokus; aplikasi harus Topmost dan aktif |
| Kartu baru tidak dikenal padahal sudah didaftarkan admin | Belum tersinkron — Menu → Status & sinkronisasi → "Sinkronkan sekarang" |
| Banner kuning "jam tablet beda …" | Jam tablet salah (§5) |
| UI tampak kecil, tombol sulit disentuh | Skala tampilan Windows belum 150% (§2) |
