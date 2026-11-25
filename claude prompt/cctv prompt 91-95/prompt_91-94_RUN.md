# Runner — Prompt 91–94 (Module CCTV)

Jalankan berurutan, tanpa berhenti menunggu persetujuan di antara prompt:

1. `claude prompt/cctv/prompt_91_cctv_schema_master.md`
2. `claude prompt/cctv/prompt_92_cctv_stream_live.md`
3. `claude prompt/cctv/prompt_93_cctv_playback.md`
4. `claude prompt/cctv/prompt_94_cctv_dari_transaksi.md`

Baca dulu `claude prompt/cctv/module-cctv-keputusan-desain.md`. Kalau prompt dan
dokumen itu bertentangan, prompt menang.

## Aturan seri

- **Cek nomor dulu.** Kalau di `claude prompt/` sudah ada prompt bernomor 91–94 untuk
  hal lain, berhenti dan tanya owner.
- **Mockup adalah arahan UI.** File di `claude prompt/cctv/mockup/*.dc.html`
  (pembungkus `<x-dc>`, `<helmet>`, dan blok `<script type="text/x-dc">` diabaikan;
  isi `<div>` root adalah layarnya). Ikuti urutan elemen, teks label/tombol (bahasa
  Indonesia persis), dan warna: aksi utama `#1F5FBF`, latar `#F5F6F8`, kotak video
  `#11161C`, online `#1B7A3D`, offline `#B42318`, peringatan `#9A3A06`. Terjemahkan ke
  Bootstrap/CSS yang ada di Client; boleh buat `wwwroot/css/cctv.css`. Nama kamera,
  area, dan data di mockup hanya contoh.

  | Mockup | Layar | Prompt |
  |---|---|---|
  | `Kamera.dc.html` | Master kamera + form ubah | 91 |
  | `Main.dc.html` | Grid live | 92 |
  | `Playback.dc.html` | Playback rekaman | 93 |
  | `Transaksi.dc.html` | Panel "CCTV saat kejadian" | 94 |

- Schema database `cctv`: tabel `cctv.<tabel>`, SP `cctv.SIS_<Nama>`. API memanggil SP
  lengkap dengan schema.
- **Eksekusi DDL langsung ke database diizinkan** untuk seri ini (seperti seri 71–77).
  Di awal Prompt 91: baca connection string dari `TerakarsaApp.API/appsettings*.json`,
  tampilkan nama server + database, lalu lanjut. Semua script tetap disimpan di
  `sql/cctv/` (idempotent) dan `sql/create_tables_tmos_final.sql` ikut diperbarui.
  Jangan DROP/ALTER objek di luar schema `cctv` (kecuali seed `Modules`).
- Setelah tiap prompt: `dotnet build TerakarsaApp.slnx -v q` harus sukses, lalu
  `git commit` dengan pesan `Prompt NN — <judul>`. Jangan push.
- Berhenti dan bertanya **hanya** kalau prompt tidak bisa dikerjakan. Keputusan kecil:
  ambil yang paling masuk akal dan catat di laporan.
- Server MediaMTX ada di `192.168.8.233`. Dari mesin development mungkin tidak
  terjangkau; kalau begitu, jangan mengarang hasil uji — tulis "tidak bisa diuji dari
  sini" di laporan.

## Laporan (WAJIB)

Isi `claude prompt/report/LAPORAN_91-94_cctv.md` — template sudah ada, **jangan ubah
judul bagiannya**, isi tiap bagian setelah prompt terkait selesai (bukan sekaligus di
akhir). Laporan ini dibaca Claude di claude.ai untuk merencanakan langkah berikutnya,
jadi tulis apa adanya: yang gagal, yang dilewati, dan yang tidak diuji harus tertulis.
Commit laporan bersama Prompt 94.

## Yang TIDAK boleh dilakukan (seluruh seri)

- Jangan menyimpan kode verifikasi / password RTSP kamera di database, kode, atau
  laporan. Terakarsa hanya bicara ke MediaMTX, tidak pernah langsung ke kamera.
- Jangan mengubah `mediamtx.yml` atau apa pun di server; kalau perlu perubahan
  konfigurasi MediaMTX, tulis di laporan bagian "Yang harus dikerjakan owner".
- Jangan membuat alamat MediaMTX bisa diakses browser tanpa lewat API Terakarsa.
- Jangan ubah SP/tabel produksi (`bundles`, `article_workflow_logs`,
  `SIS_WorkflowLog_Manage`, dst). Seri ini hanya **membaca** `resources`, `divisions`,
  `users`.
- Jangan membuat peta pabrik / denah (di luar versi pertama).
- Jangan refactor kode lama di luar cakupan.
