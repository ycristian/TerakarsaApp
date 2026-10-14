// Module Stok Benang (Prompt 71): deteksi lebar layar.
//
// Halaman /gudang/benang punya dua tata letak (mockup owner): <= 899px satu kolom
// (klik SKU -> buka halaman detail) dan >= 900px dua panel (klik SKU -> isi panel
// kanan). Blazor tidak bisa membaca breakpoint CSS, jadi halaman menanyakannya ke
// sini sekali saat render pertama dan ikut mendengarkan perubahan ukuran layar
// (rotasi HP / tablet).
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
