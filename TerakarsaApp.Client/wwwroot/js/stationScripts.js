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
