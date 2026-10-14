// Module Stok Benang (Prompt 71): deteksi lebar layar.
//
// Halaman /gudang/benang punya dua tata letak (mockup owner): <= 899px satu kolom
// (klik SKU -> buka halaman detail) dan >= 900px dua panel (klik SKU -> isi panel
// kanan). Blazor tidak bisa membaca breakpoint CSS, jadi halaman menanyakannya ke
// sini sekali saat render pertama dan ikut mendengarkan perubahan ukuran layar
// (rotasi HP / tablet).
// Prompt 73: QR untuk PREVIEW label 30x20 mm di layar (bukan yang dicetak -- yang
// dicetak dirender ulang di PrintService lewat QRCoder). Memakai qrcodejs lokal
// (wwwroot/lib/qrcodejs), library yang sama dengan window.qrCodeRenderer; dibuat
// terpisah karena preview label butuh ukuran kecil (±110 px), sedangkan
// qrCodeRenderer dipakai modal pairing station dengan ukuran tetap 200 px --
// qrCode.js TIDAK disentuh.
window.benangQr = (function () {
    return {
        render: function (elementId, text, size) {
            var el = document.getElementById(elementId);
            if (!el || typeof QRCode === "undefined") return;

            el.innerHTML = "";
            new QRCode(el, {
                text: text,
                width: size || 110,
                height: size || 110,
                colorDark: "#1b1f24",
                colorLight: "#ffffff",
                correctLevel: QRCode.CorrectLevel.M
            });
        }
    };
})();

window.benangLayout = (function () {
    var WIDE_MIN = 900;      // samakan dengan @media (min-width: 900px) di benang.css
    var listeners = [];

    function isWide() {
        return window.innerWidth >= WIDE_MIN;
    }

    window.addEventListener('resize', function () {
        var wide = isWide();
        listeners.forEach(function (l) {
            if (l.lastValue !== wide) {
                l.lastValue = wide;
                l.ref.invokeMethodAsync('LebarBerubah', wide);
            }
        });
    });

    return {
        isWide: isWide,

        // dotNetRef: DotNetObjectReference komponen halaman, harus punya
        // [JSInvokable] LebarBerubah(bool wide).
        subscribe: function (dotNetRef) {
            listeners.push({ ref: dotNetRef, lastValue: isWide() });
            return isWide();
        },

        unsubscribe: function (dotNetRef) {
            listeners = listeners.filter(function (l) { return l.ref !== dotNetRef; });
        }
    };
})();
