// Prompt 92-94: pemutar video module CCTV.
// - hls.js dimuat LOKAL (wwwroot/lib/hls.js/hls.min.js), bukan CDN.
// - Semua URL menuju rute proxy API Terakarsa (api/cctv/...), tidak pernah ke MediaMTX.
// - Token stream (?t=) ditambahkan ke SETIAP request hls.js (playlist & segmen) lewat xhrSetup;
//   isi playlist tidak ditulis ulang server.
// - Video selalu muted (tanpa audio).
// - 2026-11-24: live view mencoba WebRTC (WHEP MediaMTX :8889) LANGSUNG dulu -- lebih stabil di
//   WiFi (paket hilang = gambar sesaat pecah, bukan berhenti & menyambung ulang). Kalau WebRTC
//   tidak tersambung (akses dari luar LAN / https / dev), otomatis pindah ke HLS lewat proxy API.
// - 2026-11-25: sinyal WHEP lewat proxy API (api/cctv/whep/{path}?t=) -- jalan juga dari
//   https://app.terakarsa.id. Kalau sinyal berhasil tapi ICE tidak pernah tersambung (browser di
//   internet, tidak menjangkau server), tab ini diingat (sessionStorage) -> kamera berikutnya
//   langsung HLS tanpa menunggu batas waktu WebRTC.
window.cctvPlayer = (function () {
    'use strict';

    var RETRY_MS = 5000;
    var MAX_RETRY = 5;
    // Setelah MAX_RETRY gagal: tampil "Tidak ada sinyal" tapi TETAP dicoba ulang dengan jeda
    // lebih panjang -- kamera sering hanya putus sementara (selama halaman masih dibuka).
    var SLOW_RETRY_MS = 20000;
    // Error jaringan fatal (WiFi tersendat): coba lanjutkan di instance hls yang sama dulu.
    var MAX_NET_RECOVER = 3;
    var NET_RECOVER_MS = 2000;
    // WebRTC: batas waktu sampai gambar tampil; putus (disconnected) lebih lama dari ini = gagal.
    var RTC_CONNECT_MS = 10000;
    var RTC_DISCONNECT_MS = 5000;
    // Sudah pernah tampil lewat WebRTC tapi gagal berturut-turut sebanyak ini -> pindah ke HLS.
    var RTC_MAX_RETRY = 2;
    // sessionStorage: WebRTC tidak terjangkau dari jaringan tab ini.
    var RTC_UNREACHABLE_KEY = 'cctv.rtcUnreachable';

    function rtcUnreachable() {
        try { return sessionStorage.getItem(RTC_UNREACHABLE_KEY) === '1'; } catch (e) { return false; }
    }
    function tandaiRtcUnreachable() {
        try { sessionStorage.setItem(RTC_UNREACHABLE_KEY, '1'); } catch (e) { }
    }

    // Kebijakan muat hls.js: timeout longgar + retry ber-backoff sebelum dianggap fatal.
    function policy(timeoutMs, retries) {
        var retry = { maxNumRetry: retries, retryDelayMs: 1000, maxRetryDelayMs: 8000 };
        return { default: {
            maxTimeToFirstByteMs: timeoutMs, maxLoadTimeMs: timeoutMs * 2,
            timeoutRetry: retry, errorRetry: retry
        } };
    }

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
        if (p.rtcTimer) { clearTimeout(p.rtcTimer); p.rtcTimer = null; }
        if (p.discTimer) { clearTimeout(p.discTimer); p.discTimer = null; }
        if (p.hls) { try { p.hls.destroy(); } catch (e) { } p.hls = null; }
        if (p.pc) { try { p.pc.close(); } catch (e) { } p.pc = null; }
        if (p.whepSession) {
            // tutup sesi WHEP di MediaMTX (tidak ditunggu)
            try { fetch(withToken(p.whepSession, p.token), { method: 'DELETE' }).catch(function () { }); } catch (e) { }
            p.whepSession = null;
        }
        var v = document.getElementById(p.id);
        if (v) {
            v.onplaying = null;
            v.onerror = null;
            try { v.pause(); } catch (e) { }
            v.srcObject = null;
            v.removeAttribute('src');
            try { v.load(); } catch (e) { }
        }
    }

    function jadwalUlang(p) {
        if (p.stopped) return;
        bersihkan(p);
        // WebRTC sempat jalan lalu gagal terus (mis. pindah jaringan) -> pakai HLS.
        if (p.mode === 'webrtc' && p.retries >= RTC_MAX_RETRY) p.mode = 'hls';
        if (p.retries >= MAX_RETRY) {
            lapor(p, 'nosignal');
            p.timer = setTimeout(function () { mulai(p); }, SLOW_RETRY_MS);
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
        // 2026-11-25: TANPA autoplay -- play() dipanggil sendiri di semua jalur (WebRTC ontrack,
        // HLS MANIFEST_PARSED, Safari). Chrome bisa menjeda video "muted autoplay" yang tidak
        // terlihat, padahal grid Live menyembunyikan kartu halaman lain dengan stream tetap jalan.
        v.autoplay = false;
        v.onplaying = function () {
            p.retries = 0; p.netRecovers = 0; p.mediaRecovered = false;
            if (p.mode === 'webrtc') p.rtcEverPlayed = true;
            lapor(p, 'playing');
        };

        if (p.mode === 'webrtc') {
            mulaiWebRtc(p, v);
            return;
        }

        if (window.Hls && window.Hls.isSupported()) {
            // Mode latensi NORMAL (bukan low-latency) + buffer lebih tebal: tayangan tertinggal
            // beberapa detik dari kamera, tapi tahan jitter WiFi -- satu segmen telat tidak
            // langsung memutus stream.
            var hls = new window.Hls({
                lowLatencyMode: false,
                liveSyncDurationCount: 4,          // putar ~4 segmen di belakang ujung live
                liveMaxLatencyDurationCount: 12,   // tertinggal lebih dari ini -> lompat ke depan
                maxBufferLength: 30,
                maxMaxBufferLength: 60,
                backBufferLength: 15,
                maxBufferHole: 1,
                nudgeMaxRetry: 10,
                enableWorker: true,
                manifestLoadPolicy: policy(15000, 4),
                playlistLoadPolicy: policy(10000, 6),
                fragLoadPolicy: policy(20000, 6),
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
                // Jaringan putus sesaat: lanjutkan muat di instance yang sama dulu (buffer
                // tetap dipakai, tanpa layar "Menyambung ulang") sebelum bongkar-pasang player.
                if (data.type === window.Hls.ErrorTypes.NETWORK_ERROR && (p.netRecovers || 0) < MAX_NET_RECOVER) {
                    p.netRecovers = (p.netRecovers || 0) + 1;
                    p.timer = setTimeout(function () {
                        p.timer = null;
                        if (p.stopped || p.hls !== hls) return;
                        try { hls.startLoad(-1); } catch (e) { jadwalUlang(p); }
                    }, NET_RECOVER_MS);
                    return;
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

    // ---------- WebRTC (WHEP MediaMTX) ----------

    function tungguIce(pc, ms) {
        return new Promise(function (resolve) {
            if (pc.iceGatheringState === 'complete') { resolve(); return; }
            var t = setTimeout(resolve, ms);
            pc.addEventListener('icegatheringstatechange', function () {
                if (pc.iceGatheringState === 'complete') { clearTimeout(t); resolve(); }
            });
        });
    }

    function gagalRtc(p, pc) {
        if (p.stopped || p.pc !== pc) return;
        if (!p.rtcEverPlayed) {
            // WebRTC belum pernah tampil (tidak terjangkau / ditolak) -> langsung HLS lewat proxy.
            // Sinyal dijawab tapi ICE tidak pernah tersambung = jaringan browser tidak menjangkau
            // server -> kamera lain di tab ini juga tidak akan bisa.
            if (p.rtcAnswered && !p.rtcIceOk) tandaiRtcUnreachable();
            p.mode = 'hls';
            bersihkan(p);
            mulai(p);
            return;
        }
        jadwalUlang(p);
    }

    function mulaiWebRtc(p, v) {
        var pc;
        try {
            pc = new RTCPeerConnection({ iceServers: [], bundlePolicy: 'max-bundle' });
        } catch (e) {
            p.mode = 'hls';
            mulai(p);
            return;
        }
        p.pc = pc;
        pc.addTransceiver('video', { direction: 'recvonly' });
        pc.addTransceiver('audio', { direction: 'recvonly' });

        pc.ontrack = function (evt) {
            if (p.pc !== pc || evt.track.kind !== 'video') return;
            v.srcObject = (evt.streams && evt.streams[0]) || new MediaStream([evt.track]);
            var pr = v.play();
            if (pr && pr.catch) pr.catch(function () { });
        };

        pc.onconnectionstatechange = function () {
            if (p.pc !== pc) return;
            var s = pc.connectionState;
            if (s === 'connected') {
                p.rtcIceOk = true;
                if (p.discTimer) { clearTimeout(p.discTimer); p.discTimer = null; }
            } else if (s === 'failed') {
                gagalRtc(p, pc);
            } else if (s === 'disconnected' && !p.discTimer) {
                // WiFi tersendat sesaat: beri waktu ICE pulih sendiri sebelum dianggap gagal.
                p.discTimer = setTimeout(function () {
                    p.discTimer = null;
                    if (p.pc === pc && pc.connectionState !== 'connected') gagalRtc(p, pc);
                }, RTC_DISCONNECT_MS);
            }
        };

        p.rtcTimer = setTimeout(function () {
            p.rtcTimer = null;
            var v2 = document.getElementById(p.id);
            if (p.pc === pc && (!v2 || v2.readyState < 2)) gagalRtc(p, pc);
        }, RTC_CONNECT_MS);

        pc.createOffer()
            .then(function (offer) { return pc.setLocalDescription(offer); })
            .then(function () { return tungguIce(pc, 2000); })
            .then(function () {
                return fetch(withToken(p.webrtcUrl, p.token), {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/sdp' },
                    body: pc.localDescription.sdp
                });
            })
            .then(function (res) {
                if (res.status !== 201) throw new Error('WHEP ' + res.status);
                var loc = res.headers.get('Location');
                if (loc && p.pc === pc) {
                    var s = new URL(loc, p.webrtcUrl);
                    s.searchParams.delete('t');
                    p.whepSession = s.toString();
                }
                if (p.pc === pc) p.rtcAnswered = true;
                return res.text();
            })
            .then(function (answer) {
                if (p.pc !== pc) return;
                return pc.setRemoteDescription({ type: 'answer', sdp: answer });
            })
            .catch(function () { gagalRtc(p, pc); });
    }

    // ---------- publik ----------

    // videoId: id elemen <video>; url: URL playlist proxy API TANPA token; key: id kamera (dikembalikan
    // ke .NET lewat OnPlayerState(key, state) -- state: playing | retrying | nosignal | unsupported).
    // webrtcUrl (opsional): endpoint WHEP -- proxy API (api/cctv/whep/{path}) atau MediaMTX
    // langsung (dev); token ?t= ditambahkan di sini. Dicoba dulu, gagal = HLS lewat url proxy.
    function start(videoId, url, token, dotnet, key, webrtcUrl) {
        stop(videoId);
        var useRtc = !!webrtcUrl && typeof window.RTCPeerConnection === 'function' && !rtcUnreachable();
        var p = { id: videoId, url: url, token: token, retries: 0, timer: null, hls: null,
                  dotnet: dotnet || null, key: key, stopped: false, mediaRecovered: false, netRecovers: 0,
                  webrtcUrl: webrtcUrl || null, mode: useRtc ? 'webrtc' : 'hls', rtcEverPlayed: false,
                  rtcAnswered: false, rtcIceOk: false,
                  pc: null, whepSession: null, rtcTimer: null, discTimer: null };
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

    function fsElement() {
        return document.fullscreenElement || document.webkitFullscreenElement || null;
    }

    function keluarFs() {
        var ex = document.exitFullscreen || document.webkitExitFullscreen;
        if (!ex || !fsElement()) return null;
        try { return ex.call(document); } catch (e) { return null; }
    }

    // Satu kamera layar penuh (klik gambar). Klik lagi = keluar. Saat dinding layar penuh aktif,
    // kamera masuk layar penuh DI ATAS dinding (bertumpuk) -- keluar kembali ke dinding.
    function fullscreen(elementId) {
        var el = document.getElementById(elementId);
        if (!el) return;
        var f = fsElement();
        if (f && (f === el || el.contains(f) || !f.contains(el))) {
            var pr = keluarFs();
            if (pr && pr.catch) pr.catch(function () { });
            return;
        }
        var req = el.requestFullscreen || el.webkitRequestFullscreen;
        if (req) {
            try { var pr2 = req.call(el); if (pr2 && pr2.catch) pr2.catch(function () { }); } catch (e) { }
            return;
        }
        // iOS Safari: hanya <video> yang bisa layar penuh
        var v = el.tagName === 'VIDEO' ? el : el.querySelector('video');
        if (v && v.webkitEnterFullscreen) v.webkitEnterFullscreen();
    }

    // ---------- dinding layar penuh (Live, 2026-11-25) ----------
    // wallEnter: Fullscreen API pada elemen dinding; perubahan dilaporkan ke .NET
    // OnFullscreenChanged(mode): 'wall' | 'other' (satu kamera di atas dinding) | 'none'.
    // Mengembalikan false bila Fullscreen API tidak ada (iPhone) -> dinding tetap tampil lewat CSS.
    var wallHandler = null;
    function lepasWallHandler() {
        if (!wallHandler) return;
        document.removeEventListener('fullscreenchange', wallHandler);
        document.removeEventListener('webkitfullscreenchange', wallHandler);
        wallHandler = null;
    }

    function wallEnter(elementId, dotnet) {
        lepasWallHandler();
        var el = document.getElementById(elementId);
        if (!el) return false;
        wallHandler = function () {
            var f = fsElement();
            var mode = !f ? 'none' : (f === el ? 'wall' : 'other');
            try { dotnet.invokeMethodAsync('OnFullscreenChanged', mode); } catch (e) { }
        };
        document.addEventListener('fullscreenchange', wallHandler);
        document.addEventListener('webkitfullscreenchange', wallHandler);
        var req = el.requestFullscreen || el.webkitRequestFullscreen;
        if (!req) return false;
        try {
            var pr = req.call(el);
            if (pr && pr.catch) pr.catch(function () { });
            return true;
        } catch (e) {
            return false;
        }
    }

    // Keluar penuh (termasuk kamera yang bertumpuk di atas dinding).
    function wallExit() {
        lepasWallHandler();
        (function lanjut() {
            var pr = keluarFs();
            if (pr && pr.then) pr.then(function () { if (fsElement()) lanjut(); }, function () { });
        })();
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

    // Lompat ke detik t di potongan yang sedang diputar -- HANYA kalau posisi itu sudah terunduh
    // (buffered). false -> .NET meminta potongan baru mulai dari posisi itu.
    // 2026-11-25: dulu `seekable` juga diterima. fMP4 dari playback MediaMTX dibuat on-the-fly dan
    // tidak mendukung byte-range, jadi lompat ke bagian yang belum terunduh (mis. "+ 10 dtk")
    // membuat browser meminta Range -> video error "Rekaman tidak bisa diputar".
    function seekTo(videoId, t) {
        var v = document.getElementById(videoId);
        if (!v || !v.src) return false;
        var r = v.buffered;
        for (var i = 0; i < r.length; i++) {
            if (t >= r.start(i) && t <= r.end(i) - 0.25) {
                v.currentTime = t;
                return true;
            }
        }
        return false;
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

    // ---------- zoom kotak (rectangle) di kotak video (2026-11-25) ----------
    // Seret kotak -> zoom ke bagian itu (boleh bertingkat, maks 8x). Kotak seleksi dikunci ke aspek
    // rasio kamera (videoWidth:videoHeight, mis. 1920:1080) sehingga hasil zoom selalu penuh dan
    // tidak gepeng. Roda mouse = zoom masuk/keluar di posisi kursor. Tombol "Reset zoom" = 1:1.
    // Klik biasa (tanpa seret) tidak diganggu (Live: klik = keluar layar penuh).
    // Murni CSS transform di <video> lewat variabel CSS di kotak -- stream tidak dimuat ulang.
    //  - Live    : aktif otomatis saat kotak .cc-video masuk layar penuh, dibuang saat keluar.
    //  - Playback: zoomEnable(id) -> aktif selama halaman terbuka; zoomDisable(id) saat dispose.
    var ZOOM_MAX = 8;
    var DRAG_MIN = 12;          // px; lebih kecil = dianggap klik
    var fsZoom = null;          // instance zoom milik kotak yang sedang layar penuh (Live)
    var pinned = {};            // elementId -> instance zoom permanen (Playback)
    var suppressClick = false;

    function zoomCreate(box, hintIdle) {
        var z = { box: box, s: 1, tx: 0, ty: 0, drag: null, hintIdle: hintIdle };

        z.sel = document.createElement('div');
        z.sel.className = 'cc-zoom-sel';
        z.ui = document.createElement('div');
        z.ui.className = 'cc-zoom-ui';
        z.info = document.createElement('span');
        z.info.className = 'cc-zoom-info';
        var reset = document.createElement('button');
        reset.type = 'button';
        reset.className = 'cc-zoom-reset';
        reset.textContent = 'Reset zoom';
        reset.addEventListener('click', function (e) {
            // jangan sampai ke handler klik Blazor (mis. keluar layar penuh)
            e.stopPropagation();
            e.preventDefault();
            zoomApply(z, 1, 0, 0);
        });
        z.ui.appendChild(z.info);
        z.ui.appendChild(reset);
        box.appendChild(z.sel);
        box.appendChild(z.ui);

        z.h = {
            down: function (e) { zoomOnDown(z, e); },
            move: function (e) { zoomOnMove(z, e); },
            up: function (e) { zoomOnUp(z, e); },
            cancel: function () { z.drag = null; z.sel.style.display = 'none'; },
            wheel: function (e) { zoomOnWheel(z, e); },
            meta: function () { zoomApply(z, z.s, z.tx, z.ty); }
        };
        box.addEventListener('pointerdown', z.h.down);
        box.addEventListener('pointermove', z.h.move);
        box.addEventListener('pointerup', z.h.up);
        box.addEventListener('pointercancel', z.h.cancel);
        box.addEventListener('wheel', z.h.wheel, { passive: false });
        // ukuran video baru diketahui / berubah (mis. ganti kualitas Sub<->Main) -> hitung ulang batas
        z.video = box.querySelector('video');
        if (z.video) z.video.addEventListener('loadedmetadata', z.h.meta);
        box.classList.add('is-zoomable');
        zoomApply(z, 1, 0, 0);
        return z;
    }

    function zoomDestroy(z) {
        if (!z) return;
        var b = z.box, h = z.h;
        b.removeEventListener('pointerdown', h.down);
        b.removeEventListener('pointermove', h.move);
        b.removeEventListener('pointerup', h.up);
        b.removeEventListener('pointercancel', h.cancel);
        b.removeEventListener('wheel', h.wheel);
        if (z.video) z.video.removeEventListener('loadedmetadata', h.meta);
        z.ui.remove();
        z.sel.remove();
        b.classList.remove('is-zoomable', 'is-zoomed');
        b.style.removeProperty('--cc-zs');
        b.style.removeProperty('--cc-zx');
        b.style.removeProperty('--cc-zy');
    }

    // Area gambar sebenarnya di dalam kotak (video object-fit: contain -> bisa ada bar hitam).
    // ar = aspek rasio kamera, cadangan 16:9 kalau belum diketahui.
    function zoomContent(z) {
        var W = z.box.clientWidth, H = z.box.clientHeight;
        var v = z.box.querySelector('video');
        var ar = v && v.videoWidth > 0 && v.videoHeight > 0 ? v.videoWidth / v.videoHeight : 16 / 9;
        var dw = Math.min(W, H * ar), dh = dw / ar;
        return { W: W, H: H, ar: ar, ox: (W - dw) / 2, oy: (H - dh) / 2, dw: dw, dh: dh };
    }

    function zoomApply(z, s, tx, ty) {
        s = Math.min(ZOOM_MAX, Math.max(1, s));
        if (s < 1.01) { s = 1; tx = 0; ty = 0; }
        // gambar hasil zoom selalu menutup area gambar (tidak pernah ada celah di dalamnya)
        var c = zoomContent(z);
        tx = Math.min(c.ox * (1 - s), Math.max((c.ox + c.dw) * (1 - s), tx));
        ty = Math.min(c.oy * (1 - s), Math.max((c.oy + c.dh) * (1 - s), ty));
        z.s = s; z.tx = tx; z.ty = ty;
        var st = z.box.style;
        st.setProperty('--cc-zs', String(s));
        st.setProperty('--cc-zx', tx + 'px');
        st.setProperty('--cc-zy', ty + 'px');
        z.box.classList.toggle('is-zoomed', s > 1);
        z.info.textContent = s > 1 ? s.toFixed(1).replace('.', ',') + '×' : z.hintIdle;
    }

    function zoomPoint(z, e) {
        var r = z.box.getBoundingClientRect();
        return {
            x: Math.min(r.width, Math.max(0, e.clientX - r.left)),
            y: Math.min(r.height, Math.max(0, e.clientY - r.top))
        };
    }

    // Kotak seleksi dikunci ke aspek rasio kamera dan tetap di dalam kotak video.
    function zoomSelRect(z, d) {
        var c = zoomContent(z);
        var dx = d.x1 - d.x0, dy = d.y1 - d.y0;
        var sx = dx < 0 ? -1 : 1, sy = dy < 0 ? -1 : 1;
        var w = Math.max(Math.abs(dx), Math.abs(dy) * c.ar);
        var availW = sx > 0 ? c.W - d.x0 : d.x0;
        var availH = sy > 0 ? c.H - d.y0 : d.y0;
        w = Math.min(w, availW, availH * c.ar);
        var h = w / c.ar;
        return { x: sx > 0 ? d.x0 : d.x0 - w, y: sy > 0 ? d.y0 : d.y0 - h, w: w, h: h };
    }

    function zoomOnDown(z, e) {
        if (e.button !== 0 || e.target.closest('.cc-zoom-ui')) return;
        var p = zoomPoint(z, e);
        z.drag = { x0: p.x, y0: p.y, x1: p.x, y1: p.y, id: e.pointerId };
        try { z.box.setPointerCapture(e.pointerId); } catch (err) { }
    }

    function zoomOnMove(z, e) {
        var d = z.drag;
        if (!d || d.id !== e.pointerId) return;
        var p = zoomPoint(z, e);
        d.x1 = p.x; d.y1 = p.y;
        var sel = z.sel.style;
        if (Math.abs(d.x1 - d.x0) < DRAG_MIN && Math.abs(d.y1 - d.y0) < DRAG_MIN) { sel.display = 'none'; return; }
        var r = zoomSelRect(z, d);
        sel.display = 'block';
        sel.left = r.x + 'px';
        sel.top = r.y + 'px';
        sel.width = r.w + 'px';
        sel.height = r.h + 'px';
    }

    function zoomOnUp(z, e) {
        var d = z.drag;
        if (!d || d.id !== e.pointerId) return;
        z.drag = null;
        z.sel.style.display = 'none';
        try { z.box.releasePointerCapture(e.pointerId); } catch (err) { }

        // klik biasa (hampir tanpa gerak) -> dibiarkan sampai ke handler klik halaman
        if (Math.abs(d.x1 - d.x0) < DRAG_MIN && Math.abs(d.y1 - d.y0) < DRAG_MIN) return;

        // seret = zoom, BUKAN klik: klik yang menyusul jangan sampai diproses halaman
        suppressClick = true;
        setTimeout(function () { suppressClick = false; }, 400);

        var r = zoomSelRect(z, d);
        if (r.w < DRAG_MIN) return;

        // kotak (koordinat layar) -> koordinat video sebelum transform, lalu dipetakan ke area
        // gambar penuh (aspek rasio sama -> tidak gepeng, tidak ada celah)
        var s = z.s, c = zoomContent(z);
        var x0 = (r.x - z.tx) / s, y0 = (r.y - z.ty) / s;
        var ns = Math.min(ZOOM_MAX, c.dw / (r.w / s));
        var cx = x0 + r.w / s / 2, cy = y0 + r.h / s / 2;
        zoomApply(z, ns, c.ox + c.dw / 2 - cx * ns, c.oy + c.dh / 2 - cy * ns);
    }

    function zoomOnWheel(z, e) {
        e.preventDefault();
        var f = e.deltaY < 0 ? 1.25 : 1 / 1.25;
        var ns = Math.min(ZOOM_MAX, Math.max(1, z.s * f));
        var p = zoomPoint(z, e);
        var cx = (p.x - z.tx) / z.s, cy = (p.y - z.ty) / z.s;
        zoomApply(z, ns, p.x - cx * ns, p.y - cy * ns);
    }

    function zoomRefreshAll() {
        if (fsZoom) zoomApply(fsZoom, fsZoom.s, fsZoom.tx, fsZoom.ty);
        Object.keys(pinned).forEach(function (k) {
            var z = pinned[k];
            zoomApply(z, z.s, z.tx, z.ty);
        });
    }

    // Live: kotak .cc-video yang sedang layar penuh (bukan kotak yang zoom-nya permanen).
    function zoomSyncFs() {
        var f = fsElement();
        var box = f && f.classList && f.classList.contains('cc-video') && !f.dataset.ccZoomPinned ? f : null;
        if (fsZoom && fsZoom.box !== box) { zoomDestroy(fsZoom); fsZoom = null; }
        if (box && !fsZoom) fsZoom = zoomCreate(box, 'Seret kotak untuk zoom · klik untuk keluar');
        zoomRefreshAll();   // ukuran kotak berubah
    }

    // Playback: zoom permanen pada kotak video.
    function zoomEnable(elementId) {
        if (pinned[elementId]) return;
        var box = document.getElementById(elementId);
        if (!box) return;
        box.dataset.ccZoomPinned = '1';
        pinned[elementId] = zoomCreate(box, 'Seret kotak untuk zoom');
    }

    function zoomDisable(elementId) {
        var z = pinned[elementId];
        if (!z) return;
        delete pinned[elementId];
        delete z.box.dataset.ccZoomPinned;
        zoomDestroy(z);
    }

    // Reset ke 1:1 (mis. ganti kamera di Playback).
    function zoomReset(elementId) {
        var z = pinned[elementId];
        if (z) zoomApply(z, 1, 0, 0);
    }

    document.addEventListener('fullscreenchange', zoomSyncFs);
    document.addEventListener('webkitfullscreenchange', zoomSyncFs);
    // Fase capture di window: jalan SEBELUM delegasi event Blazor.
    window.addEventListener('click', function (e) {
        if (!suppressClick) return;
        suppressClick = false;
        e.stopPropagation();
        e.preventDefault();
    }, true);
    window.addEventListener('resize', zoomRefreshAll);

    return {
        start: start, setToken: setToken, stop: stop, stopAll: stopAll, fullscreen: fullscreen,
        wallEnter: wallEnter, wallExit: wallExit,
        watchVisibility: watchVisibility, unwatchVisibility: unwatchVisibility,
        playClip: playClip, clipInfo: clipInfo, seekBy: seekBy, seekTo: seekTo, togglePause: togglePause,
        setRate: setRate, stopClip: stopClip, download: download, clickRatio: clickRatio,
        zoomEnable: zoomEnable, zoomDisable: zoomDisable, zoomReset: zoomReset
    };
})();
