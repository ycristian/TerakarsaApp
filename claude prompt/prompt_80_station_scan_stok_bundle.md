# Prompt 80 — Station Bundling: Scan Stok Bundle & Kunci Cutting

Lanjutan Prompt 78–79. Baca `claude prompt/cutting/module-cutting-keputusan-desain.md` §6.

## 0. Inspeksi dulu
Periksa dan ringkas di awal jawaban: bagaimana Station Bundling menerima bundle dari Cutting sekarang (SP `SIS_WorkflowLog_Manage` / `SIS_Bundle_Manage`, action apa, log step mana yang ditulis, counterpart resource), dan bagaimana scan QR kamera dipakai di station (komponen yang ada).

## 1. Scan Stok Bundle di Station Bundling

- Tambah aksi **Scan Stok Bundle** di station yang punya resource divisi Bundling (hanya tampil kalau resource station = Bundling). Mode scan kamera + input manual kode bundle (pola scan station yang ada).
- Scan QR → cari bundle: harus `source=CUTTING` dan `stock_status=STOCK`. Tampilkan kartu konfirmasi: kode, PO · artikel, size, qty, rentang nomor, hamparan. Bisa scan beberapa dulu (daftar), lalu **Ambil N bundle**.
- Ambil → SP baru `SIS_CuttingBundle_Take` (@bundle_ids, @resource_id, @station): dalam satu transaksi set `stock_status=TAKEN`, `taken_at`, `taken_by_resource_id`, **lalu panggil jalur penerimaan bundle yang sudah ada** supaya workflow log Cutting → Bundling tertulis persis seperti penerimaan bundle manual sekarang (jangan duplikasi logika; panggil SP/langkah yang ditemukan di inspeksi). Bundle yang bukan STOCK → tolak dengan pesan ("sudah diambil Line 3 pada 14 Okt 15:10" / "bukan bundle cutting").
- Setelah diambil, bundle masuk tab/alur station seperti bundle lain. Tidak ada perubahan di tab IN/OUT.

## 2. Kunci di sisi cutting
Sudah diguard di SP Prompt 78 (`UPDATE_QTY`, `REMOVE`, `DELETE` spread tolak kalau TAKEN). Pastikan UI Detail Hamparan membaca `taken_at` + nama resource pengambil dari `SIS_Spread_Detail` dan tombol Edit nonaktif.

## 3. Bundle manual tetap jalan
Alur buat bundle lama (admin) tidak diubah; bundle `source=MANUAL` tidak muncul di stok cutting dan tidak bisa discan lewat Scan Stok Bundle.

## 4. Stok Bundle: pengambilan hari ini
Di halaman Stok Bundle (Prompt 78) tambah panel kecil "Diambil hari ini": daftar kode bundle · line · jam (data dari `taken_at` hari ini). Dari Detail Hamparan, bundle TAKEN menampilkan line + waktu (sudah di mockup).

## 5. App Android "Terakarsa" — pilihan tujuan
- Di layar pilih tujuan setelah login (Prompt 76), tambah **Admin Cutting** → `/cutting`, tampil hanya kalau user punya module `CUTTING` (pola sama dengan Admin Gudang / PO TNI). Kalau daftar tujuan diambil dari API, cukup tambah di sumber datanya; kalau hardcoded di app, tambah entri + ikon. Kamera di WebView sudah diteruskan, jadi scan di station tidak perlu perubahan.
- Bump versi APK dan sertakan di laporan.

## 6. Verifikasi
- Build lolos (API, client, dan MAUI). Uji: scan bundle STOCK di station Bundling → TAKEN, workflow log Cutting→Bundling muncul sama persis dengan penerimaan manual (bandingkan kolom per kolom, tulis di laporan). Scan ulang bundle yang sama → ditolak. Edit qty bundle TAKEN dari halaman cutting → ditolak.
- Laporan akhir: ringkas + "Catatan".
