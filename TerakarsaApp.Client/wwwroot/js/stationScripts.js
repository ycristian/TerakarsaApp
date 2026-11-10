// Dipakai SearchableSelect.razor untuk menghitung ruang kosong di atas/bawah input,
// supaya dropdown bisa membatasi tinggi atau membalik arah kalau viewport pendek.
window.getDropdownSpace = (el) => {
    if (!el) return { spaceBelow: 0, spaceAbove: 0 };
    const rect = el.getBoundingClientRect();
    return {
        spaceBelow: window.innerHeight - rect.bottom,
        spaceAbove: rect.top
    };
};

window.copyToClipboard = (text) => {
    if (window.isSecureContext && navigator.clipboard) {
        return navigator.clipboard.writeText(text);
    }

    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();

    let succeeded = false;
    try {
        succeeded = document.execCommand("copy");
    } finally {
        document.body.removeChild(textarea);
    }

    return succeeded ? Promise.resolve() : Promise.reject(new Error("Copy gagal, browser tidak mendukung."));
};

// Prompt 58: tap sel di Rekap absen -> pindah ke sub-tab Input lalu gulirkan baris pegawai
// yang ditap ke tengah layar. Elemen bisa belum ada (mis. tersaring pencarian) -- diam saja.
window.scrollElementIntoView = (elementId) => {
    const el = document.getElementById(elementId);
    if (el) el.scrollIntoView({ behavior: "smooth", block: "center" });
};

// Prompt 85: nama perangkat default untuk /station di browser biasa (app Android menyuntik
// namanya sendiri). Model HP tidak tersedia -- Chrome sengaja menyembunyikannya dari user agent.
window.stationDeviceLabel = () => {
    const ua = navigator.userAgent || "";
    const browser = /Edg\//.test(ua) ? "Edge"
        : /SamsungBrowser\//.test(ua) ? "Samsung Internet"
        : /Firefox\//.test(ua) ? "Firefox"
        : /Chrome\//.test(ua) ? "Chrome"
        : /Safari\//.test(ua) ? "Safari"
        : "Browser";
    const os = /Android/.test(ua) ? "Android"
        : /iPhone|iPad|iPod/.test(ua) ? "iOS"
        : /Windows/.test(ua) ? "Windows"
        : /Mac OS X/.test(ua) ? "macOS"
        : /Linux/.test(ua) ? "Linux"
        : "";
    return os ? `${browser} · ${os}` : browser;
};
