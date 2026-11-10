// Prompt 66: pemindai QR untuk module PDH TNI AD (html5-qrcode dari file lokal
// wwwroot/lib/html5-qrcode -- BUKAN CDN, supaya scan tetap jalan tanpa internet).
//
// BEDANYA dengan window.qrScanner (qrScanner.js, dipakai station):
//   - kamera TIDAK berhenti setelah satu hasil -- staff scan ratusan kartu per hari
//     dan tidak boleh menekan tombol tiap kartu;
//   - teks yang sama diabaikan kalau terbaca lagi dalam 3 detik (kartu masih di
//     depan kamera);
//   - ada bunyi + getar sebagai umpan balik;
//   - minta Wake Lock supaya layar tidak mati selama kamera aktif.
//
// qrScanner.js TIDAK disentuh.
//
// Prompt 72: halaman /gudang/benang/scan (module Stok Benang) MEMAKAI ULANG pemindai
// ini apa adanya -- tidak ada isi khusus TNI di dalamnya. Kalau perilakunya harus
// berbeda untuk salah satu module, pisahkan dulu sebelum mengubah.
window.tniScanner = (() => {
    let instance = null;
    let wakeLock = null;
    let audioCtx = null;

    // teks terakhir + waktunya, untuk mengabaikan bacaan dobel
    let lastText = null;
    let lastAt = 0;
    const DEDUPE_MS = 3000;

    async function requestWakeLock() {
        try {
            if ("wakeLock" in navigator) {
                wakeLock = await navigator.wakeLock.request("screen");
                // kalau layar sempat mati/tab pindah, lock dilepas browser -- biarkan.
                wakeLock.addEventListener("release", () => { wakeLock = null; });
            }
        } catch (e) {
            // Wake Lock tidak didukung / ditolak -- bukan error yang perlu dilaporkan.
        }
    }

    async function releaseWakeLock() {
        try {
            if (wakeLock) { await wakeLock.release(); }
        } catch (e) {
            // abaikan
        }
        wakeLock = null;
    }

    // 2026-11-09: browser HP (terutama iOS) membiarkan AudioContext "suspended" kalau
    // dibuat/di-resume DI LUAR sentuhan user -- padahal bunyi scan dipicu hasil server,
    // bukan sentuhan. Jadi audio dibuka di setiap sentuhan/tombol (pilih box, mulai
    // kamera, dst.), plus satu buffer senyap untuk "membuka kunci" audio iOS.
    let audioUnlocked = false;

    function ensureAudio() {
        try {
            audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
            if (audioCtx.state === "suspended") audioCtx.resume();

            if (!audioUnlocked) {
                const buf = audioCtx.createBuffer(1, 1, 22050);
                const src = audioCtx.createBufferSource();
                src.buffer = buf;
                src.connect(audioCtx.destination);
                src.start(0);
                audioUnlocked = true;
            }
        } catch (e) {
            // perangkat tanpa audio -- abaikan
        }
    }

    ["pointerdown", "touchend", "keydown"].forEach((ev) =>
        document.addEventListener(ev, ensureAudio, { capture: true, passive: true }));

    // Satu aturan dedupe untuk kamera DAN scanner Bluetooth (Prompt 90): teks yang
    // sama dalam 3 detik diabaikan. true = boleh diproses (dan dicatat sebagai bacaan
    // terakhir).
    function lolosDedupe(text) {
        const now = Date.now();
        if (text === lastText && now - lastAt < DEDUPE_MS) return false;
        lastText = text;
        lastAt = now;
        return true;
    }

    // ---------- Prompt 90: keyboard wedge (scanner Bluetooth mode HID) ----------
    // Scanner mengetik isi QR sebagai keystroke cepat (< 20 ms/karakter) lalu Enter.
    // Ketikan manusia jauh lebih lambat -> jeda > WEDGE_GAP_MS mengosongkan buffer,
    // jadi ketikan di kolom lain tidak pernah dianggap scan.
    const WEDGE_GAP_MS = 50;
    const WEDGE_MIN_LEN = 4;
    let wedgeRef = null;
    let wedgeMethod = "OnScanned";
    let wedgeBuf = "";
    let wedgeLastAt = 0;

    function onWedgeKeydown(e) {
        if (!wedgeRef) return;

        // Kolom yang memang diketik manusia (kotak manual, form pembatalan).
        const t = e.target;
        if (t && t.closest && t.closest("[data-wedge-ignore]")) {
            wedgeBuf = "";
            return;
        }

        // shortcut (Ctrl/Cmd/Alt) bukan ketikan scanner
        if (e.ctrlKey || e.metaKey || e.altKey) return;

        const now = Date.now();
        const gap = now - wedgeLastAt;

        if (e.key === "Enter" || e.key === "Tab") {
            const text = gap <= WEDGE_GAP_MS ? wedgeBuf : "";
            wedgeBuf = "";
            if (text.length < WEDGE_MIN_LEN) return;   // Enter/Tab biasa -- biarkan

            // Jangan sampai Enter "menekan" tombol yang sedang fokus / Tab pindah fokus.
            e.preventDefault();
            e.stopPropagation();

            if (!lolosDedupe(text)) return;
            wedgeRef.invokeMethodAsync(wedgeMethod, text).catch(() => { /* halaman sudah ditutup */ });
            return;
        }

        // Shift dsb. (key lebih dari 1 karakter) tidak memutus buffer.
        if (!e.key || e.key.length !== 1) return;

        if (gap > WEDGE_GAP_MS) wedgeBuf = "";
        wedgeBuf += e.key;
        wedgeLastAt = now;
    }

    function stopKeyboard() {
        document.removeEventListener("keydown", onWedgeKeydown, { capture: true });
        wedgeRef = null;
        wedgeBuf = "";
        wedgeLastAt = 0;
    }

    const VOLUME = 0.25;      // dulu 0.08 -- terlalu pelan di ruang produksi
    const JEDA_MS = 45;       // jeda antarnada; tanpa jeda dua nada sama terdengar satu bunyi panjang

    // Bunyi pendek lewat WebAudio -- tidak butuh file audio.
    function beep(freqs, durationMs) {
        try {
            ensureAudio();

            let startAt = audioCtx.currentTime + 0.01;
            freqs.forEach((f) => {
                const osc = audioCtx.createOscillator();
                const gain = audioCtx.createGain();
                osc.type = "square";
                osc.frequency.value = f;
                gain.gain.value = VOLUME;
                osc.connect(gain);
                gain.connect(audioCtx.destination);
                osc.start(startAt);
                osc.stop(startAt + durationMs / 1000);
                startAt += (durationMs + JEDA_MS) / 1000;
            });
        } catch (e) {
            // perangkat tanpa audio -- abaikan
        }
    }

    return {
        start: async function (elementId, dotNetRef) {
            if (typeof Html5Qrcode === "undefined") {
                await dotNetRef.invokeMethodAsync("OnScanError", "Pustaka pemindai QR gagal dimuat.");
                return;
            }

            // sudah jalan -- jangan start dua kali
            if (instance) return;

            lastText = null;
            lastAt = 0;
            instance = new Html5Qrcode(elementId);

            try {
                await instance.start(
                    { facingMode: "environment" },
                    { fps: 10, qrbox: { width: 250, height: 250 } },
                    async (decodedText) => {
                        // Kartu yang sama masih di depan kamera -> abaikan.
                        if (!lolosDedupe(decodedText)) return;

                        // Kamera SENGAJA dibiarkan menyala.
                        await dotNetRef.invokeMethodAsync("OnScanned", decodedText);
                    },
                    () => {
                        // belum ketemu QR di frame ini -- bukan error
                    }
                );

                await requestWakeLock();
            } catch (err) {
                instance = null;
                await releaseWakeLock();
                await dotNetRef.invokeMethodAsync(
                    "OnScanError",
                    "Tidak bisa mengakses kamera: " + (err && err.message ? err.message : err));
            }
        },

        stop: async function () {
            stopKeyboard();   // Prompt 90: listener wedge tidak boleh bocor ke halaman lain
            await releaseWakeLock();
            if (!instance) return;
            const active = instance;
            instance = null;
            try {
                await active.stop();
                active.clear();
            } catch (e) {
                // kamera mungkin sudah berhenti -- abaikan
            }
        },

        // Dipanggil Blazor setelah tahu hasil dari server, bukan saat QR terbaca --
        // supaya bunyinya mencerminkan hasil sebenarnya (OK / SUDAH / gagal).
        //   ok         1 bip tinggi
        //   sudah      2 bip sedang
        //   konfirmasi 4 nada naik-turun (perlu tindakan: pop up menunggu jawaban)
        //   lainnya    1 bunyi rendah panjang (gagal)
        feedback: function (jenis) {
            if (jenis === "ok") {
                beep([1320], 90);
                if (navigator.vibrate) navigator.vibrate(60);
            } else if (jenis === "konfirmasi") {
                beep([660, 990, 660, 990], 110);
                if (navigator.vibrate) navigator.vibrate([90, 60, 90, 60, 90]);
            } else if (jenis === "sudah") {
                beep([880, 880], 80);
                if (navigator.vibrate) navigator.vibrate([50, 60, 50]);
            } else {
                beep([320], 220);
                if (navigator.vibrate) navigator.vibrate(300);
            }
        },

        // Lupakan bacaan terakhir -- dipakai saat input manual supaya kartu yang sama
        // boleh langsung di-scan lagi.
        resetDedupe: function () {
            lastText = null;
            lastAt = 0;
        },

        // Prompt 90: scanner Bluetooth (HID / keyboard emulation). Tidak butuh kotak
        // input yang fokus -- listener dipasang di document. Bunyi TIDAK dibunyikan di
        // sini: Blazor memanggil feedback() setelah tahu hasil server, sama dengan kamera.
        // methodName opsional (default "OnScanned") supaya halaman bisa membedakan
        // sumber wedge dari kamera.
        startKeyboard: function (dotNetRef, methodName) {
            stopKeyboard();   // start ulang = ganti ref, bukan menumpuk listener
            wedgeRef = dotNetRef;
            wedgeMethod = methodName || "OnScanned";
            document.addEventListener("keydown", onWedgeKeydown, { capture: true });
        },

        stopKeyboard: stopKeyboard,

        // Dedupe yang sama untuk input dari kotak manual (scanner menembak saat kotak
        // fokus). true = boleh diproses.
        cekDedupe: function (text) {
            return lolosDedupe(text);
        }
    };
})();
