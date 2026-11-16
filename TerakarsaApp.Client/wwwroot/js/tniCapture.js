// 2026-11-10: tombol "Salin gambar" di kartu Kekurangan stok (Perintah Kerja).
// Tabel digambar ulang ke <canvas> dari data yang sama (tanpa library screenshot),
// lalu PNG-nya disalin ke clipboard supaya bisa langsung di-paste ke WhatsApp.
// Clipboard gambar hanya jalan di HTTPS/localhost -- selain itu (atau bila browser
// menolak) PNG diunduh sebagai file. Hasil: "COPY" | "DOWNLOAD".
window.tniCapture = (() => {
    const C = {
        navy: "#042C53", ink: "#1B2430", mut: "#6B7685",
        line: "#E3E7EC", head: "#F1F3F6", grp: "#E8EDF3", bad: "#C0392B"
    };
    const SANS = "system-ui, -apple-system, 'Segoe UI', Roboto, Arial, sans-serif";

    // data = { judul, info: [[label, nilai], ...], tabel: [{ label, baris: [{ grp, kode, qty }] }], namaFile }
    function gambar(data) {
        const S = 2;                 // skala supaya tajam di HP
        const pad = 12, gap = 8, colW = 170, rowH = 20, headH = 22;
        // lebar = tabel, atau baris info terpanjang bila lebih lebar
        // (mis. "Gabungan 4 satuan prioritas (DBKG, DARM, ...)") supaya tidak terpotong.
        const ukur = document.createElement("canvas").getContext("2d");
        const lebarInfo = Math.max(0, ...data.info.map(([label, nilai]) => {
            ukur.font = `12px ${SANS}`;
            const w = ukur.measureText(label + " ").width;
            ukur.font = `700 12px ${SANS}`;
            return w + ukur.measureText(nilai).width;
        }));
        const lebarTabel = data.tabel.length * colW + (data.tabel.length - 1) * gap;
        const lebar = Math.ceil(pad * 2 + Math.max(lebarTabel, lebarInfo));
        const atas = pad + 18 + data.info.length * 16 + 6;
        const maxBaris = Math.max(...data.tabel.map(t => t.baris.length));
        const tinggi = atas + headH + maxBaris * rowH + pad;

        const cv = document.createElement("canvas");
        cv.width = lebar * S; cv.height = tinggi * S;
        const g = cv.getContext("2d");
        g.scale(S, S);
        g.textBaseline = "middle";

        g.fillStyle = "#fff"; g.fillRect(0, 0, lebar, tinggi);
        g.strokeStyle = C.bad; g.lineWidth = 1;
        g.strokeRect(0.5, 0.5, lebar - 1, tinggi - 1);

        g.fillStyle = C.mut; g.font = `700 12px ${SANS}`;
        g.fillText(data.judul, pad, pad + 8);
        data.info.forEach(([label, nilai], i) => {
            const y = pad + 26 + i * 16;
            g.font = `12px ${SANS}`; g.fillStyle = C.mut;
            g.fillText(label, pad, y);
            const w = g.measureText(label + " ").width;
            g.font = `700 12px ${SANS}`; g.fillStyle = C.ink;
            g.fillText(nilai, pad + w, y);
        });

        data.tabel.forEach((t, ti) => {
            const x = pad + ti * (colW + gap);
            const h = headH + t.baris.length * rowH;
            const kanan = x + colW - 8;

            g.fillStyle = C.head; g.fillRect(x, atas, colW, headH);
            g.fillStyle = C.ink; g.font = `600 12px ${SANS}`;
            g.textAlign = "left"; g.fillText(t.label, x + 8, atas + headH / 2);
            g.textAlign = "right"; g.fillText("Kurang", kanan, atas + headH / 2);

            t.baris.forEach((b, i) => {
                const y = atas + headH + i * rowH;
                const tengah = y + rowH / 2;
                if (b.grp) {
                    g.fillStyle = C.grp; g.fillRect(x, y, colW, rowH);
                    g.fillStyle = C.navy; g.font = `700 11.5px ${SANS}`;
                    g.textAlign = "left"; g.fillText(b.kode, x + 8, tengah);
                } else {
                    // size = teks biasa (tanpa tag), permintaan owner 2026-11-10
                    g.fillStyle = C.ink; g.font = `11.5px ${SANS}`;
                    g.textAlign = "left"; g.fillText(b.kode, x + 8, tengah);
                    g.font = `700 11.5px ${SANS}`;
                }
                g.textAlign = "right"; g.fillText(String(b.qty), kanan, tengah);
                g.strokeStyle = C.line;
                g.beginPath(); g.moveTo(x, y + 0.5); g.lineTo(x + colW, y + 0.5); g.stroke();
            });

            g.strokeStyle = C.line; g.strokeRect(x + 0.5, atas + 0.5, colW - 1, h - 1);
            g.textAlign = "left";
        });

        return cv;
    }

    async function salin(data) {
        const cv = gambar(data);
        const blob = await new Promise(r => cv.toBlob(r, "image/png"));

        if (window.isSecureContext && navigator.clipboard && window.ClipboardItem) {
            try {
                await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]);
                return "COPY";
            } catch { /* jatuh ke unduh */ }
        }

        const a = document.createElement("a");
        a.href = URL.createObjectURL(blob);
        a.download = data.namaFile || "kekurangan-stok.png";
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(() => URL.revokeObjectURL(a.href), 5000);
        return "DOWNLOAD";
    }

    return { salin };
})();
