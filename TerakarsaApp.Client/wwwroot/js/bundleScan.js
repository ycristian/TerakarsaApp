// Interop kamera untuk panel "Scan Bundle" (/station) dan halaman publik /b/{serial}.
// Memakai html5-qrcode dari file lokal (wwwroot/lib/html5-qrcode), bukan CDN.
window.bundleScanner = (() => {
    let html5QrCode = null;

    return {
        start: async function (elementId, dotNetRef) {
            if (typeof Html5Qrcode === "undefined") {
                console.error("html5-qrcode belum termuat.");
                return false;
            }

            try {
                html5QrCode = new Html5Qrcode(elementId);
                await html5QrCode.start(
                    { facingMode: "environment" },
                    { fps: 10, qrbox: { width: 250, height: 250 } },
                    (decodedText) => {
                        dotNetRef.invokeMethodAsync("OnScanResult", decodedText);
                    },
                    () => { /* decode gagal per-frame, abaikan */ }
                );
                return true;
            } catch (err) {
                console.error("Gagal memulai kamera:", err);
                return false;
            }
        },

        stop: async function () {
            if (html5QrCode) {
                try {
                    await html5QrCode.stop();
                    html5QrCode.clear();
                } catch (err) {
                    // sudah berhenti / elemen sudah dilepas, abaikan
                }
                html5QrCode = null;
            }
        }
    };
})();
