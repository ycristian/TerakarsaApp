// Render QR code link pairing station (modal admin di /stations) supaya bisa langsung
// discan dari tablet/HP ke URL /station/{kode}, tanpa ketik manual. Memakai qrcodejs
// (davidshimjs) dari file lokal (wwwroot/lib/qrcodejs), bukan CDN -- sama pola dengan
// html5-qrcode untuk pemindaian di bundleScan.js.
window.qrCodeRenderer = (() => {
    let instance = null;

    return {
        render: function (elementId, text) {
            const el = document.getElementById(elementId);
            if (!el || typeof QRCode === "undefined") return;

            el.innerHTML = "";
            instance = new QRCode(el, {
                text: text,
                width: 200,
                height: 200,
                colorDark: "#000000",
                colorLight: "#ffffff",
                correctLevel: QRCode.CorrectLevel.M
            });
        },

        clear: function (elementId) {
            const el = document.getElementById(elementId);
            if (el) el.innerHTML = "";
            instance = null;
        }
    };
})();
