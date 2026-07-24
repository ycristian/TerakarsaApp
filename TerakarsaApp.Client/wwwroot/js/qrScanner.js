// Pemindaian QR lewat kamera (html5-qrcode, file lokal wwwroot/lib/html5-qrcode --
// bukan CDN, pola sama dengan qrcodejs untuk generate di qrCode.js). QR pada label
// selalu berisi URL ({PublicBaseUrl}/b/{serial} atau /pack/{serial}) -- hasil scan
// diteruskan ke Blazor (QrScannerModal.razor) yang lalu NavigationManager.NavigateTo
// ke path-nya, TANPA membuka tab baru/window baru.
window.qrScanner = (() => {
    let instance = null;

    return {
        start: async function (elementId, dotNetRef) {
            if (typeof Html5Qrcode === "undefined") {
                await dotNetRef.invokeMethodAsync("OnScanError", "Pustaka pemindai QR gagal dimuat.");
                return;
            }

            instance = new Html5Qrcode(elementId);

            try {
                await instance.start(
                    { facingMode: "environment" },
                    { fps: 10, qrbox: { width: 250, height: 250 } },
                    async (decodedText) => {
                        // Cegah callback dobel kalau stop() sudah dipanggil (mis. user
                        // tekan Batal tepat saat QR baru saja kebaca).
                        if (!instance) return;
                        const active = instance;
                        instance = null;
                        try {
                            await active.stop();
                            active.clear();
                        } catch (e) {
                            // Abaikan -- kamera mungkin sudah berhenti duluan.
                        }
                        await dotNetRef.invokeMethodAsync("OnScanned", decodedText);
                    },
                    () => {
                        // Callback per-frame saat belum ketemu QR -- diabaikan, bukan error.
                    }
                );
            } catch (err) {
                instance = null;
                await dotNetRef.invokeMethodAsync("OnScanError", "Tidak bisa mengakses kamera: " + (err && err.message ? err.message : err));
            }
        },

        stop: async function () {
            if (!instance) return;
            const active = instance;
            instance = null;
            try {
                await active.stop();
                active.clear();
            } catch (e) {
                // Kamera mungkin sudah berhenti/belum sempat start -- aman diabaikan.
            }
        }
    };
})();
