// Delegated close-on-backdrop-click and close-on-Esc for the app's
// `<div class="modal d-block">...` popup pattern (Bootstrap-styled, but not
// Bootstrap's JS modal component). Works for every modal in the app without
// each .razor file wiring its own handler, because every modal's close button
// already carries the correct Blazor @onclick (Batal/X) — this just clicks it
// on the app's behalf.
(function () {
    function closeButtonOf(modalEl) {
        var btn = modalEl.querySelector('.modal-header .btn-close');
        return (btn && !btn.disabled) ? btn : null;
    }

    document.addEventListener('click', function (e) {
        var target = e.target;
        if (target && target.classList && target.classList.contains('modal') && target.classList.contains('d-block')) {
            var closeBtn = closeButtonOf(target);
            if (closeBtn) {
                closeBtn.click();
            }
        }
    });

    document.addEventListener('keydown', function (e) {
        if (e.key !== 'Escape' && e.key !== 'Esc') {
            return;
        }
        var modals = document.querySelectorAll('.modal.d-block');
        if (modals.length === 0) {
            return;
        }
        // Last in DOM order = most recently opened / topmost.
        var topModal = modals[modals.length - 1];
        var closeBtn = closeButtonOf(topModal);
        if (closeBtn) {
            closeBtn.click();
        }
    });
})();
