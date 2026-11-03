/**
 * File: assets/js/auth.js
 * Session, guard, login/logout.
 * Frontend hanya untuk UX. Semua otorisasi sebenarnya di RLS + RPC.
 */
(function() {
  const sb = () => window.cvsSupabase;
  
  async function getSession() {
    const { data, error } = await sb().auth.getSession();
    if (error) return null;
    return data.session || null;
  }
  
  async function getProfile() {
    const session = await getSession();
    if (!session) return null;
    const { data, error } = await sb()
      .from('profiles')
      .select('id, email, full_name, role, is_active')
      .eq('id', session.user.id)
      .single();
    if (error) return null;
    return data;
  }
  
  /**
   * Guard halaman protected.
   * @param {Object} opts { roles?: string[] }
   * @returns {Promise<Object|null>} profile atau null (redirect terjadi)
   */
  async function requireAuth(opts = {}) {
    const session = await getSession();
    if (!session) {
      window.location.href = '/login';
      return null;
    }
    const profile = await getProfile();
    if (!profile || profile.is_active === false) {
      await sb().auth.signOut();
      window.location.href = '/login';
      return null;
    }
    if (opts.roles && !opts.roles.includes(profile.role)) {
      window.location.href = '/dashboard';
      return null;
    }
    return profile;
  }
  
  async function login(email, password) {
    const { data, error } = await sb().auth.signInWithPassword({ email, password });
    if (error) throw error;
    const profile = await getProfile();
    if (!profile || profile.is_active === false) {
      await sb().auth.signOut();
      throw new Error('Akun tidak aktif atau tidak terdaftar.');
    }
    return data;
  }
  
  async function logout() {
    await sb().auth.signOut();
    window.location.href = '/login';
  }
  
  window.CVSAuth = { getSession, getProfile, requireAuth, login, logout };
})();