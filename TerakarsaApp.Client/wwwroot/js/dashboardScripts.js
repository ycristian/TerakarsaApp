// Per-page script loader for the Home dashboard (charts, datatable, world map).
// Blazor has no @section Scripts like Razor Pages, so these libraries are only
// injected while Home.razor is on screen instead of being loaded globally in index.html.
(function () {
    const libraryScripts = [
        'assets/plugins/chart/Chart.bundle.js',
        'assets/plugins/chart/rounded-barchart.js',
        'assets/plugins/chart/utils.js',
        'assets/plugins/flot/jquery.flot.js',
        'assets/plugins/flot/jquery.flot.fillbetween.js',
        'assets/plugins/flot/chart.flot.sampledata.js',
        'assets/plugins/flot/dashboard.sampledata.js',
        'assets/plugins/datatable/js/jquery.dataTables.min.js',
        'assets/plugins/datatable/js/dataTables.bootstrap5.js',
        'assets/plugins/datatable/dataTables.responsive.min.js',
        'assets/plugins/jvectormap/jquery-jvectormap-2.0.2.min.js',
        'assets/plugins/jvectormap/jquery-jvectormap-world-mill-en.js'
    ];

    function loadScriptOnce(src) {
        return new Promise((resolve, reject) => {
            if (document.querySelector(`script[src="${src}"]`)) {
                resolve();
                return;
            }
            const script = document.createElement('script');
            script.src = src;
            script.onload = () => resolve();
            script.onerror = () => reject(new Error(`Failed to load ${src}`));
            document.body.appendChild(script);
        });
    }

    function loadScriptFresh(src) {
        return new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.src = src;
            script.dataset.dashboardInit = 'true';
            script.onload = () => resolve();
            script.onerror = () => reject(new Error(`Failed to load ${src}`));
            document.body.appendChild(script);
        });
    }

    window.loadDashboardScripts = async function () {
        for (const src of libraryScripts) {
            await loadScriptOnce(src);
        }

        // Re-injected fresh every mount: they run init code (charts/datatable/map)
        // against the canvases/tables that exist in the DOM right now.
        await loadScriptFresh('assets/js/index1.js');
        await loadScriptFresh('assets/js/themeColors.js');
    };

    window.unloadDashboardScripts = function () {
        document.querySelectorAll('script[data-dashboard-init="true"]').forEach(s => s.remove());
    };
})();
