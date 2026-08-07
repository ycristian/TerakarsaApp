// Prompt 51: grafik tab "Tren" (harian) & "Per Jam" pada LineDetailModal.razor. Memakai
// Chart.js (assets/plugins/chart/Chart.bundle.js, v2.7.3) yang SUDAH ada di proyek (dipakai
// Home.razor demo lewat dashboardScripts.js) -- di sini dimuat lazy on-demand (pola sama dengan
// loadScriptOnce di dashboardScripts.js) karena LineDetailModal tampil di /tv-dashboard yang
// TIDAK memuat Chart.js secara default. TIDAK menambah library baru.
window.lineDetailCharts = (() => {
    const charts = {};

    const COLORS = {
        ok: '#198754',       // hijau -- Qty OK, konsisten dgn palet dashboard (text-success)
        terima: '#0d6efd',   // biru -- Terima
        gray: '#6c757d',     // abu -- garis target & arsir istirahat
        grayBg: 'rgba(108, 117, 125, 0.15)',
    };

    let chartJsPromise = null;
    function loadChartJs() {
        if (window.Chart) return Promise.resolve();
        if (chartJsPromise) return chartJsPromise;
        chartJsPromise = new Promise((resolve, reject) => {
            const src = 'assets/plugins/chart/Chart.bundle.js';
            if (document.querySelector(`script[src="${src}"]`)) {
                const check = () => window.Chart ? resolve() : setTimeout(check, 30);
                check();
                return;
            }
            const script = document.createElement('script');
            script.src = src;
            script.onload = () => resolve();
            script.onerror = () => reject(new Error('Gagal memuat Chart.js'));
            document.body.appendChild(script);
        });
        return chartJsPromise;
    }

    function destroy(canvasId) {
        if (charts[canvasId]) {
            charts[canvasId].destroy();
            delete charts[canvasId];
        }
    }

    // Plugin custom (bukan library baru -- cuma objek hook Chart.js) yg menggambar latar abu
    // transparan di belakang bar pada indeks jam istirahat, supaya kekosongan itu kelihatan
    // "wajar" alih-alih seperti data hilang.
    function breakShadingPlugin(breakFlags) {
        return {
            beforeDraw: function (chartInstance) {
                if (!breakFlags || !breakFlags.some(f => f)) return;
                const ctx = chartInstance.ctx;
                const xAxis = chartInstance.scales['x-axis-0'];
                const yAxis = chartInstance.scales['y-axis-0'];
                if (!xAxis || !yAxis) return;
                ctx.save();
                ctx.fillStyle = COLORS.grayBg;
                const slotWidth = (xAxis.right - xAxis.left) / breakFlags.length;
                breakFlags.forEach((isBreak, i) => {
                    if (!isBreak) return;
                    const left = xAxis.left + (slotWidth * i);
                    ctx.fillRect(left, yAxis.top, slotWidth, yAxis.bottom - yAxis.top);
                });
                ctx.restore();
            }
        };
    }

    // Garis target horizontal putus-putus melintang seluruh lebar grafik (Bagian 3 prompt 51).
    // Digambar manual (bukan dataset) supaya tidak muncul di legend/tooltip sbg seri ketiga.
    function targetLinePlugin(targetValue) {
        return {
            afterDraw: function (chartInstance) {
                if (targetValue === null || targetValue === undefined) return;
                const ctx = chartInstance.ctx;
                const xAxis = chartInstance.scales['x-axis-0'];
                const yAxis = chartInstance.scales['y-axis-0'];
                if (!xAxis || !yAxis) return;
                const y = yAxis.getPixelForValue(targetValue);
                ctx.save();
                ctx.strokeStyle = COLORS.gray;
                ctx.setLineDash([6, 4]);
                ctx.lineWidth = 1.5;
                ctx.beginPath();
                ctx.moveTo(xAxis.left, y);
                ctx.lineTo(xAxis.right, y);
                ctx.stroke();
                ctx.restore();
            }
        };
    }

    return {
        // Tab "Tren", grafik harian: line chart, Terima putus-putus + Qty OK penuh, y mulai 0,
        // tooltip mode index (Bagian 2a prompt 51).
        renderTrend: async function (canvasId, labels, terima, ok) {
            await loadChartJs();
            destroy(canvasId);
            const el = document.getElementById(canvasId);
            if (!el) return;
            charts[canvasId] = new Chart(el.getContext('2d'), {
                type: 'line',
                data: {
                    labels: labels,
                    datasets: [
                        {
                            label: 'Terima',
                            data: terima,
                            borderColor: COLORS.terima,
                            backgroundColor: 'transparent',
                            borderDash: [6, 4],
                            fill: false,
                            pointRadius: 2,
                            borderWidth: 2,
                        },
                        {
                            label: 'Qty OK',
                            data: ok,
                            borderColor: COLORS.ok,
                            backgroundColor: 'transparent',
                            fill: false,
                            pointRadius: 2,
                            borderWidth: 2,
                        },
                    ],
                },
                options: {
                    maintainAspectRatio: false,
                    responsive: true,
                    tooltips: { mode: 'index', intersect: false },
                    scales: {
                        yAxes: [{ ticks: { beginAtZero: true } }],
                    },
                },
            });
        },

        // Tab "Per Jam": bar chart berdampingan, Qty OK + Terima, jam istirahat diarsir + batang
        // null, garis target/jam putus-putus (Bagian 3 prompt 51).
        renderHourly: async function (canvasId, labels, terima, ok, breakFlags, targetPerJam) {
            await loadChartJs();
            destroy(canvasId);
            const el = document.getElementById(canvasId);
            if (!el) return;
            charts[canvasId] = new Chart(el.getContext('2d'), {
                type: 'bar',
                data: {
                    labels: labels,
                    datasets: [
                        { label: 'Qty OK', data: ok, backgroundColor: COLORS.ok },
                        { label: 'Terima', data: terima, backgroundColor: COLORS.terima },
                    ],
                },
                options: {
                    maintainAspectRatio: false,
                    responsive: true,
                    tooltips: { mode: 'index', intersect: false },
                    scales: {
                        yAxes: [{ ticks: { beginAtZero: true } }],
                    },
                },
                plugins: [breakShadingPlugin(breakFlags), targetLinePlugin(targetPerJam)],
            });
        },

        destroy: destroy,
    };
})();
