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
