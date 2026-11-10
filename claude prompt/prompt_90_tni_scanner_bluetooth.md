# Prompt 90 — PDH TNI AD: Dukungan Scanner Bluetooth (keyboard emulation) di `/tni/scan`

> Lanjutan seri PDH TNI AD. Aturan seri: CLAUDE.md bagian "Module PDH TNI AD".
> Jangan ubah alur kamera (`tniScanner.js`) dan logika proses scan yang ada —
> hanya menambah SUMBER input baru yang masuk ke jalur yang sama.

## Konteks

Staff packing akan memakai **scanner Bluetooth mode HID (keyboard emulation)**
— Iware X203 (2D, Auto-Sense di stand, support iOS) — yang dipasangkan ke iPad,
bukan kamera. Scanner mengetik isi QR sebagai keystroke cepat lalu mengirim
Enter. Isi QR kartu = URL penuh `https://app.terakarsa.id/t/<qr_token>`; untuk
QR rusak staff mengetik `kode_ref` manual.

Halaman `/tni/scan` (Prompt 66–68) sudah punya `OnScanned(string)` →
`AmbilToken()` → `antrean` → `ProsesAntreanAsync()`. Semua aturan di situ
(mode SET buka pop up konfirmasi, mode BOX langsung catat, jeda `kodeDitutup`,
abaikan scan saat pop up terbuka) **harus berlaku sama** untuk input scanner
Bluetooth. Referensi pola input manual: `Pages/Gudang/Benang/Scan.razor`
(Prompt 72), tapi di sini kotak input tidak boleh menjadi syarat — scanner harus
tetap terbaca meski staff tidak menyentuh kotak apa pun.

Browser tidak bisa membaca Bluetooth serial (SPP) — tidak perlu Web Bluetooth.

## 1. JS — `wwwroot/js/tniScanner.js` (tambahan, bukan ubah fungsi lama)

Tambah "keyboard wedge" di objek `window.tniScanner`:

- `startKeyboard(dotNetRef)` / `stopKeyboard()`.
- Pasang `keydown` di `document` (capture). Kumpulkan karakter printable ke
  buffer. Saat `Enter`/`Tab`: kalau buffer ≥ 4 karakter → panggil
  `dotNetRef.invokeMethodAsync("OnScanned", buffer)`, kosongkan buffer,
  `preventDefault`.
- **Pembeda ketikan manusia vs scanner**: jeda antar karakter > 50 ms → buffer
  di-reset (scanner mengetik < 20 ms/karakter). Jadi ketikan manusia di
  textarea komplain / kolom lain tidak ikut tertangkap.
- Kalau fokus sedang di `<input>`/`<textarea>` yang punya atribut
  `data-wedge-ignore`, abaikan sama sekali (untuk kolom yang memang diketik
  manusia, mis. form pembatalan).
- **Dedupe 3 detik yang sudah ada DIPAKAI juga di sini** — scanner Auto-Sense
  di stand akan menembak kartu yang sama berulang kalau kartu didiamkan di
  depannya. Pakai fungsi dedupe/`resetDedupe` yang sama dengan kamera supaya
  perilakunya seragam.
- Bunyi: panggil `feedback()` yang sudah ada supaya suara sukses/gagal sama
  dengan kamera.
- `stop()` yang lama juga memanggil `stopKeyboard()` supaya listener tidak
  bocor saat pindah halaman.

## 2. Client — `Pages/Tni/Scan.razor`

- Di `OnAfterRenderAsync` setelah `tniScanner.start`: panggil
  `tniScanner.startKeyboard(selfRef)`. Kalau kamera gagal (`kameraError`),
  keyboard wedge **tetap jalan** — ini justru kasus utamanya di iPad.
- `DisposeAsync`: panggil `stopKeyboard`.
- Tambah kotak **"Kode manual / scanner Bluetooth"** di bawah kamera (pakai
  field `kodeManual` yang sudah ada): `@onkeydown` Enter → `OnScanned(kodeManual)`
  → kosongkan. Beri `data-wedge-ignore` supaya tidak diproses dua kali saat
  scanner menembak ketika kotak ini sedang fokus.
- Indikator kecil di header: ikon bluetooth/keyboard + teks "Scanner siap"
  setelah tembakan pertama tertangkap lewat wedge (state `wedgeAktif`), supaya
  staff tahu scanner terbaca tanpa harus melihat hasil.
- Banner `kameraError` diubah: "Kamera tidak tersedia — scanner Bluetooth tetap
  bisa dipakai, atau ketik kode di kotak bawah."
- Catatan iPad: saat scanner HID tersambung, keyboard layar iPad hilang. Tulis
  di `tni-note` bawah kotak manual: "Keyboard layar hilang? Tekan tombol
  keyboard di scanner."

## 3. Halaman lain yang memakai `tniScanner`

`TokenPublic.razor` (sheet "Scan QR lain") dan `Gudang/Benang/Scan.razor`
**tidak** diubah di prompt ini. Benang sudah punya kotak manual; kalau nanti mau
wedge global, tinggal panggil `startKeyboard`.

## 4. Uji

1. Chrome desktop: ketik cepat lewat script (`dispatchEvent` keydown < 20 ms)
   `https://app.terakarsa.id/t/<token valid>` + Enter → mode SET membuka pop up
   konfirmasi; mode BOX langsung tercatat ke box aktif.
2. Tembakan yang sama dua kali dalam 3 detik → hanya diproses sekali (dedupe).
3. Ketik `kode_ref` manual perlahan di kotak bawah + Enter → diproses lewat
   kotak, **tidak** dobel lewat wedge.
4. Ketik perlahan di textarea komplain / form pembatalan lalu Enter → tidak
   memicu scan.
5. Pindah ke halaman lain lalu kembali → listener tidak dobel (cek jumlah
   invoke per tembakan = 1).
6. iPad Safari + Iware X203: tembak kartu tanpa menyentuh layar → terbaca;
   karakter `:` dan `/` utuh (kalau berubah = layout keyboard, bukan bug app —
   catat di "Catatan").

## Catatan

Keputusan kecil ambil sendiri dan catat di sini. Commit: `Prompt 90: scanner
Bluetooth (keyboard wedge) di /tni/scan`.

### Dikerjakan 2026-11-09

- **Dedupe**: cek inline di callback kamera dipindah ke fungsi `lolosDedupe(text)`
  yang dipakai kamera + wedge (perilaku kamera identik; `lastText/lastAt` sama,
  jadi kamera dan scanner saling dedupe untuk kartu yang sama).
- **`startKeyboard(dotNetRef, methodName)`**: parameter kedua opsional (default
  `"OnScanned"`). `/tni/scan` memakai `OnWedgeScanned` → menyalakan `wedgeAktif`
  lalu meneruskan ke `OnScanned` (jalur proses sama). Tanpa ini Blazor tidak bisa
  membedakan tembakan wedge dari kamera untuk indikator "Scanner siap".
  `startKeyboard` dua kali = ganti ref, bukan listener ganda.
- **Urutan start**: `startKeyboard` dipanggil SEBELUM `tniScanner.start`, bukan
  sesudah — `start` menunggu dialog izin kamera; kalau staff tidak menjawab, wedge
  tidak akan pernah jalan.
- **Bunyi**: wedge tidak membunyikan apa pun di JS. Bunyi datang dari
  `feedback()` yang dipanggil Blazor setelah hasil server (sama persis dengan
  kamera); bunyi di JS akan dobel.
- **Enter/Tab** ditelan (`preventDefault`) hanya kalau buffer ≥ 4 karakter dan
  jeda ke karakter terakhir ≤ 50 ms — Enter manusia di tombol/kolom tetap normal.
  Ctrl/Cmd/Alt diabaikan; Shift (key > 1 karakter) tidak memutus buffer.
- **Kotak manual**: Enter → `EnterKotakManualAsync` = `cekDedupe` (dedupe JS yang
  sama) → `OnScanned` (jeda pop up `kodeDitutup` tetap berlaku). Tombol **Catat**
  tetap `ScanManualAsync` lama (reset dedupe = sengaja). Alasan: scanner Auto-Sense
  yang menembak saat kotak fokus harus diperlakukan sama dengan wedge.
  Ditambah `autocomplete/autocapitalize/autocorrect/spellcheck` off supaya iPad
  tidak mengubah huruf kode.
- **`data-wedge-ignore`** juga dipasang di kolom alasan `TniAjukanBatal.razor`
  (form pembatalan; komponen bersama, tidak berpengaruh di halaman tanpa wedge).
- **Uji**: 1/2/4/5 diuji di Chromium (Playwright, halaman uji lokal + ref .NET
  palsu): tembakan cepat = 1 invoke & tombol fokus tidak ter-klik, ulang < 3 dtk =
  0, ketikan pelan di textarea = 0, kolom `data-wedge-ignore` = 0, setelah
  `stop()` = 0, `startKeyboard` dua kali = 1 invoke. Uji 3 (kotak manual) dan
  uji 6 (iPad Safari + Iware X203, karakter `:` `/`) BELUM — perlu perangkat.
