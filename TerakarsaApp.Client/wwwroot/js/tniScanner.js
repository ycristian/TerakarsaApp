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

    // Bunyi pendek lewat WebAudio -- tidak butuh file audio.
    function beep(freqs, durationMs) {
        try {
            audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
            if (audioCtx.state === "suspended") audioCtx.resume();

            let startAt = audioCtx.currentTime;
            freqs.forEach((f) => {
                const osc = audioCtx.createOscillator();
                const gain = audioCtx.createGain();
                osc.type = "square";
                osc.frequency.value = f;
                gain.gain.value = 0.08;
                osc.connect(gain);
                gain.connect(audioCtx.destination);
                osc.start(startAt);
                osc.stop(startAt + durationMs / 1000);
                startAt += durationMs / 1000;
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
                        const now = Date.now();
                        // Kartu yang sama masih di depan kamera -> abaikan.
                        if (decodedText === lastText && now - lastAt < DEDUPE_MS) return;
                        lastText = decodedText;
                        lastAt = now;

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
        feedback: function (jenis) {
            if (jenis === "ok") {
                beep([1320], 90);
                if (navigator.vibrate) navigator.vibrate(60);
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
        }
    };
})();
