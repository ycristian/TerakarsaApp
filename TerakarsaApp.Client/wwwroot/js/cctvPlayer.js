// Prompt 92-94: pemutar video module CCTV.
// - hls.js dimuat LOKAL (wwwroot/lib/hls.js/hls.min.js), bukan CDN.
// - Semua URL menuju rute proxy API Terakarsa (api/cctv/...), tidak pernah ke MediaMTX.
// - Token stream (?t=) ditambahkan ke SETIAP request hls.js (playlist & segmen) lewat xhrSetup;
//   isi playlist tidak ditulis ulang server.
// - Video selalu muted (tanpa audio).
window.cctvPlayer = (function () {
    'use strict';

    var RETRY_MS = 5000;
    var MAX_RETRY = 5;

    // id elemen video -> { hls, url, token, retries, timer, dotnet, key, stopped }
    var players = {};

    function withToken(url, token) {
        var u = new URL(url, document.baseURI);
        u.searchParams.delete('t');
        if (token) u.searchParams.set('t', token);
        return u.toString();
    }

    function lapor(p, state) {
        if (p.dotnet) {
            try { p.dotnet.invokeMethodAsync('OnPlayerState', p.key, state); } catch (e) { /* komponen sudah dibuang */ }
        }
    }

    function bersihkan(p) {
        if (p.timer) { clearTimeout(p.timer); p.timer = null; }
        if (p.hls) { try { p.hls.destroy(); } catch (e) { } p.hls = null; }
        var v = document.getElementById(p.id);
        if (v) {
            v.onplaying = null;
            v.onerror = null;
            try { v.pause(); } catch (e) { }
            v.removeAttribute('src');
            try { v.load(); } catch (e) { }
        }
    }

    function jadwalUlang(p) {
        if (p.stopped) return;
        bersihkan(p);
        if (p.retries >= MAX_RETRY) {
            lapor(p, 'nosignal');
            return;
        }
        p.retries++;
        lapor(p, 'retrying');
        p.timer = setTimeout(function () { mulai(p); }, RETRY_MS);
    }

    function mulai(p) {
        if (p.stopped) return;
        var v = document.getElementById(p.id);
        if (!v) return;

        v.muted = true;
        v.defaultMuted = true;
        v.playsInline = true;
        v.autoplay = true;
        v.onplaying = function () { p.retries = 0; lapor(p, 'playing'); };

        if (window.Hls && window.Hls.isSupported()) {
            var hls = new window.Hls({
                lowLatencyMode: true,
                liveSyncDurationCount: 3,
                maxBufferLength: 10,
                backBufferLength: 10,
                enableWorker: true,
                xhrSetup: function (xhr, url) {
                    // token terbaru (bisa diperbarui setToken saat stream berjalan)
                    xhr.open('GET', withToken(url, p.token), true);
                }
            });
            p.hls = hls;
            hls.on(window.Hls.Events.ERROR, function (evt, data) {
                if (!data || !data.fatal) return;
                if (data.type === window.Hls.ErrorTypes.MEDIA_ERROR && !p.mediaRecovered) {
                    p.mediaRecovered = true;
                    try { hls.recoverMediaError(); return; } catch (e) { }
                }
                jadwalUlang(p);
            });
            hls.loadSource(p.url);
            hls.attachMedia(v);
            hls.on(window.Hls.Events.MANIFEST_PARSED, function () {
                var pr = v.play();
                if (pr && pr.catch) pr.catch(function () { });
            });
        } else if (v.canPlayType('application/vnd.apple.mpegurl')) {
            // Safari/iOS tanpa MSE: playlist bertingkat & segmen TIDAK membawa ?t= -> kemungkinan 401.
            v.onerror = function () { jadwalUlang(p); };
            v.src = withToken(p.url, p.token);
            var pr2 = v.play();
            if (pr2 && pr2.catch) pr2.catch(function () { });
        } else {
            lapor(p, 'unsupported');
        }
    }

    // ---------- publik ----------

    // videoId: id elemen <video>; url: URL playlist proxy API TANPA token; key: id kamera (dikembalikan
    // ke .NET lewat OnPlayerState(key, state) -- state: playing | retrying | nosignal | unsupported).
    function start(videoId, url, token, dotnet, key) {
        stop(videoId);
        var p = { id: videoId, url: url, token: token, retries: 0, timer: null, hls: null,
                  dotnet: dotnet || null, key: key, stopped: false, mediaRecovered: false };
        players[videoId] = p;
        mulai(p);
    }

    function setToken(videoId, token) {
        var p = players[videoId];
        if (p) p.token = token;
    }

    function stop(videoId) {
        var p = players[videoId];
        if (!p) return;
        p.stopped = true;
        bersihkan(p);
        delete players[videoId];
    }

    function stopAll() {
        Object.keys(players).forEach(stop);
    }

    function fullscreen(elementId) {
        var el = document.getElementById(elementId);
        if (!el) return;
        if (document.fullscreenElement) { document.exitFullscreen(); return; }
        if (el.requestFullscreen) { el.requestFullscreen(); return; }
        // iOS Safari: hanya <video> yang bisa layar penuh
        var v = el.tagName === 'VIDEO' ? el : el.querySelector('video');
        if (v && v.webkitEnterFullscreen) v.webkitEnterFullscreen();
    }

    // visibilitychange -> .NET OnVisibilityChanged(hidden)
    var visHandler = null;
    function watchVisibility(dotnet) {
        unwatchVisibility();
        visHandler = function () {
            try { dotnet.invokeMethodAsync('OnVisibilityChanged', document.hidden); } catch (e) { }
        };
        document.addEventListener('visibilitychange', visHandler);
    }
    function unwatchVisibility() {
        if (visHandler) document.removeEventListener('visibilitychange', visHandler);
        visHandler = null;
    }

    // ---------- rekaman (Prompt 93-94): <video src> progresif, token di query ----------
    // Satu potongan rekaman = satu URL fMP4/MP4 dari rute playback proxy API.
    function playClip(videoId, url, dotnet, key, startAtSec, rate) {
        var v = document.getElementById(videoId);
        if (!v) return;
        stop(videoId);
        v.muted = true;
        v.playsInline = true;
        v.onplaying = function () { if (dotnet) dotnet.invokeMethodAsync('OnClipState', key, 'playing'); };
        v.onended = function () { if (dotnet) dotnet.invokeMethodAsync('OnClipState', key, 'ended'); };
        v.onerror = function () { if (dotnet) dotnet.invokeMethodAsync('OnClipState', key, 'error'); };
        v.onloadedmetadata = function () {
            if (startAtSec && startAtSec > 0) { try { v.currentTime = startAtSec; } catch (e) { } }
            if (rate) v.playbackRate = rate;
        };
        v.src = url;
        var pr = v.play();
        if (pr && pr.catch) pr.catch(function () { });
    }

    function clipInfo(videoId) {
        var v = document.getElementById(videoId);
        if (!v) return null;
        return { currentTime: v.currentTime || 0, paused: v.paused, duration: isFinite(v.duration) ? v.duration : 0 };
    }

    function seekBy(videoId, delta) {
        var v = document.getElementById(videoId);
        if (!v) return 0;
        var t = Math.max(0, (v.currentTime || 0) + delta);
        if (isFinite(v.duration) && v.duration > 0) t = Math.min(t, v.duration - 0.1);
        v.currentTime = t;
        return t;
    }

    // Lompat ke detik t di potongan yang sedang diputar -- hanya kalau posisi itu bisa
    // dicari (seekable/buffered). false -> .NET meminta potongan baru mulai dari posisi itu.
    function seekTo(videoId, t) {
        var v = document.getElementById(videoId);
        if (!v || !v.src) return false;
        function dalam(r) {
            for (var i = 0; i < r.length; i++) { if (t >= r.start(i) && t <= r.end(i)) return true; }
            return false;
        }
        if (!dalam(v.seekable) && !dalam(v.buffered)) return false;
        v.currentTime = t;
        return true;
    }

    function togglePause(videoId) {
        var v = document.getElementById(videoId);
        if (!v) return true;
        if (v.paused) { var pr = v.play(); if (pr && pr.catch) pr.catch(function () { }); return false; }
        v.pause();
        return true;
    }

    function setRate(videoId, rate) {
        var v = document.getElementById(videoId);
        if (v) v.playbackRate = rate;
    }

    function stopClip(videoId) {
        var v = document.getElementById(videoId);
        if (!v) return;
        v.onplaying = v.onended = v.onerror = v.onloadedmetadata = null;
        try { v.pause(); } catch (e) { }
        v.removeAttribute('src');
        try { v.load(); } catch (e) { }
    }

    // Unduh lewat <a download> -- URL proxy API sudah membawa token ?t= dan
    // Content-Disposition: attachment, jadi browser langsung menyimpan file.
    function download(url) {
        var a = document.createElement('a');
        a.href = url;
        a.rel = 'noopener';
        a.download = '';
        document.body.appendChild(a);
        a.click();
        a.remove();
    }

    // posisi klik relatif (0..1) di elemen -- untuk garis waktu
    function clickRatio(elementId, clientX) {
        var el = document.getElementById(elementId);
        if (!el) return -1;
        var r = el.getBoundingClientRect();
        if (r.width <= 0) return -1;
        return Math.min(1, Math.max(0, (clientX - r.left) / r.width));
    }

    return {
        start: start, setToken: setToken, stop: stop, stopAll: stopAll, fullscreen: fullscreen,
        watchVisibility: watchVisibility, unwatchVisibility: unwatchVisibility,
        playClip: playClip, clipInfo: clipInfo, seekBy: seekBy, seekTo: seekTo, togglePause: togglePause,
        setRate: setRate, stopClip: stopClip, download: download, clickRatio: clickRatio
    };
})();
