/**
 * File: assets/js/ui.js
 * Toast, loading overlay, modal, escapeHtml, format helpers.
 */
(function () {
  // --- Inject container ---
  function ensureContainers() {
    if (!document.querySelector('.cvs-toast-container')) {
      const c = document.createElement('div');
      c.className = 'cvs-toast-container';
      document.body.appendChild(c);
    }
    if (!document.querySelector('.cvs-overlay')) {
      const o = document.createElement('div');
      o.className = 'cvs-overlay';
      o.innerHTML = '<div class="cvs-spinner"></div>';
      document.body.appendChild(o);
    }
  }

  function toast(message, type = 'info', duration = 3000) {
    ensureContainers();
    const c = document.querySelector('.cvs-toast-container');
    const el = document.createElement('div');
    el.className = 'cvs-toast ' + type;
    el.textContent = message;
    c.appendChild(el);
    requestAnimationFrame(() => el.classList.add('show'));
    setTimeout(() => {
      el.classList.remove('show');
      setTimeout(() => el.remove(), 250);
    }, duration);
  }

  function showLoading(show) {
    ensureContainers();
    const o = document.querySelector('.cvs-overlay');
    o.classList.toggle('show', !!show);
  }

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  /**
   * Modal sederhana berbasis promise.
   * @param {Object} opts { title, bodyHtml, okText, cancelText, onOpen }
   * @returns {Promise<boolean>} resolve true bila OK, false bila cancel
   */
  function modal(opts) {
    return new Promise((resolve) => {
      const backdrop = document.createElement('div');
      backdrop.className = 'cvs-modal-backdrop show';
      backdrop.innerHTML =
        '<div class="cvs-modal" role="dialog" aria-modal="true">' +
          '<div class="cvs-modal-header">' +
            '<div class="cvs-modal-title">' + escapeHtml(opts.title || '') + '</div>' +
            '<button type="button" class="cvs-modal-close" data-close>&times;</button>' +
          '</div>' +
          '<div class="cvs-modal-body">' + (opts.bodyHtml || '') + '</div>' +
          '<div class="cvs-modal-footer">' +
            '<button type="button" class="btn btn-ghost" data-close>' +
              escapeHtml(opts.cancelText || 'Batal') +
            '</button>' +
            '<button type="button" class="btn btn-primary" data-ok>' +
              escapeHtml(opts.okText || 'Simpan') +
            '</button>' +
          '</div>' +
        '</div>';
      document.body.appendChild(backdrop);

      const close = (result) => {
        backdrop.remove();
        resolve(result);
      };
      backdrop.addEventListener('click', (e) => {
        if (e.target === backdrop || e.target.hasAttribute('data-close')) close(false);
      });
      const okBtn = backdrop.querySelector('[data-ok]');
      okBtn.addEventListener('click', () => {
        if (typeof opts.onOk === 'function') {
          const r = opts.onOk(backdrop);
          if (r === false) return;
        }
        close(true);
      });
      if (typeof opts.onOpen === 'function') opts.onOpen(backdrop);
    });
  }

  function confirmDialog(message, opts = {}) {
    return modal({
      title: opts.title || 'Konfirmasi',
      bodyHtml: '<p>' + escapeHtml(message) + '</p>',
      okText: opts.okText || 'Ya',
      cancelText: opts.cancelText || 'Batal'
    });
  }

  function formatDateTime(iso) {
    if (!iso) return '-';
    return new Date(iso).toLocaleString('id-ID', {
      day: '2-digit', month: 'short', year: 'numeric',
      hour: '2-digit', minute: '2-digit'
    });
  }

  ensureContainers();

  window.CVSUI = { toast, showLoading, escapeHtml, modal, confirmDialog, formatDateTime };
})();