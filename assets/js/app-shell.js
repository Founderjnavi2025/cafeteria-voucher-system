/**
 * File: assets/js/app-shell.js
 * Membangun layout reusable: sidebar, topbar, guard, mobile drawer.
 *
 * Cara pakai di halaman protected:
 *   <body>
 *     <div id="app"></div>
 *     <script src="...app-shell.js"></script>
 *     <script>
 *       CVSAppShell.mount({
 *         title: 'Dashboard',
 *         requiredRoles: ['admin','operator','viewer'],
 *         onReady: async (profile) => { ... }
 *       });
 *     </script>
 *   </body>
 */
(function () {

  const NAV = [
    { href: '/dashboard',    label: 'Dashboard',   icon: '◉', roles: ['admin','operator','viewer'] },
    { href: '/employees',    label: 'Karyawan',    icon: '👥', roles: ['admin','operator','viewer'] },
    { href: '/attendance',   label: 'Kehadiran',   icon: '🗓', roles: ['admin','operator','viewer'] },
    { href: '/eligibility',  label: 'Slot & Aturan', icon: '⚙', roles: ['admin','operator','viewer'] },
    { href: '/scan',         label: 'Scan Voucher', icon: '🎫', roles: ['admin','operator'] },
    { href: '/vouchers',     label: 'Daftar Voucher', icon: '📄', roles: ['admin','operator','viewer'] }
  ];

  function renderShell(root, profile, title, onReady) {
    const roleLabel = profile.role === 'admin' ? 'Admin'
                    : profile.role === 'operator' ? 'Operator'
                    : profile.role === 'viewer' ? 'Viewer' : profile.role;

    const path = window.location.pathname;
    const navHtml = NAV
      .filter(item => item.roles.includes(profile.role))
      .map(item => {
        const active = (path === item.href || path === item.href + '.html') ? 'active' : '';
        return '<a href="' + item.href + '" class="' + active + '">' +
               '<span class="nav-icon">' + item.icon + '</span>' +
               '<span>' + item.label + '</span></a>';
      }).join('');

    root.innerHTML =
      '<div class="app-shell">' +
        '<aside class="sidebar" id="sidebar">' +
          '<div class="brand">' +
            '<span class="brand-mark">C</span>' +
            '<span>CVS</span>' +
          '</div>' +
          '<nav>' + navHtml + '</nav>' +
          '<div class="user-box">' +
            '<b>' + CVSUI.escapeHtml(profile.full_name || profile.email) + '</b>' +
            '<span>' + CVSUI.escapeHtml(roleLabel) + ' &middot; ' +
              CVSUI.escapeHtml(profile.email) + '</span>' +
            '<div><button class="logout-btn" id="btn-logout">Keluar</button></div>' +
          '</div>' +
        '</aside>' +
        '<div class="sidebar-backdrop" id="sidebar-backdrop"></div>' +
        '<div>' +
          '<header class="topbar">' +
            '<div class="flex items-center gap-2">' +
              '<button class="menu-toggle" id="btn-menu">☰</button>' +
              '<h1>' + CVSUI.escapeHtml(title) + '</h1>' +
            '</div>' +
            '<div class="actions" id="topbar-actions"></div>' +
          '</header>' +
          '<main class="main" id="main-content"></main>' +
        '</div>' +
      '</div>';

    // Drawer toggle
    const sidebar = document.getElementById('sidebar');
    const backdrop = document.getElementById('sidebar-backdrop');
    const btnMenu = document.getElementById('btn-menu');
    function closeDrawer() { sidebar.classList.remove('open'); backdrop.classList.remove('show'); }
    btnMenu.addEventListener('click', () => {
      sidebar.classList.add('open');
      backdrop.classList.add('show');
    });
    backdrop.addEventListener('click', closeDrawer);
    sidebar.querySelectorAll('a').forEach(a => a.addEventListener('click', closeDrawer));

    // Logout
    document.getElementById('btn-logout').addEventListener('click', async () => {
      if (await CVSUI.confirmDialog('Keluar dari aplikasi?', { okText: 'Keluar' })) {
        CVSAuth.logout();
      }
    });

    if (typeof onReady === 'function') onReady(profile);
  }

  async function mount(opts = {}) {
    const root = document.getElementById('app');
    if (!root) {
      console.error('[CVS] Elemen #app tidak ditemukan');
      return;
    }

    // Pastikan library ada
    if (!window.cvsSupabase) {
      root.innerHTML = '<div class="auth-layout"><div class="auth-card card">' +
        '<h2>Konfigurasi belum lengkap</h2>' +
        '<p class="text-muted">Isi <code>SUPABASE_URL</code> dan <code>SUPABASE_ANON_KEY</code> di <code>assets/js/config.js</code>, ' +
        'atau lewat environment Vercel.</p></div></div>';
      return;
    }

    CVSUI.showLoading(true);
    try {
      const profile = await CVSAuth.requireAuth({ roles: opts.requiredRoles });
      if (!profile) return;

      renderShell(root, profile, opts.title || CVS_CONFIG.APP_NAME, opts.onReady);
    } finally {
      CVSUI.showLoading(false);
    }
  }

  window.CVSAppShell = { mount };
})();
