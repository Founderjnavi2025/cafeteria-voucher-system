
/**
 * File: assets/js/auth.js
 * Session, guard, login/logout.
 * Frontend hanya untuk UX.
 * Otorisasi tetap di RLS + RPC.
 */
(function () {
  const sb = () => {
    if (!window.cvsSupabase) {
      throw new Error('Supabase client belum tersedia.');
    }
    return window.cvsSupabase;
  };

  async function withTimeout(promise, label, ms = 12000) {
    let timer;

    try {
      return await Promise.race([
        promise,
        new Promise((_, reject) => {
          timer = setTimeout(
            () => reject(new Error(label + ' timeout')),
            ms
          );
        })
      ]);
    } finally {
      clearTimeout(timer);
    }
  }

  async function getSession() {
    try {
      const { data, error } = await withTimeout(
        sb().auth.getSession(),
        'Memeriksa sesi'
      );

      if (error) throw error;
      return data.session || null;
    } catch (error) {
      console.error('[CVS Auth] getSession:', error);
      return null;
    }
  }

  async function getProfile() {
    const session = await getSession();
    if (!session) return null;

    try {
      const { data, error } = await withTimeout(
        sb()
          .from('profiles')
          .select('id, email, full_name, role, is_active')
          .eq('id', session.user.id)
          .single(),
        'Memuat profil'
      );

      if (error) throw error;
      return data;
    } catch (error) {
      console.error('[CVS Auth] getProfile:', error);
      return null;
    }
  }

  async function requireAuth(opts = {}) {
    const session = await getSession();

    if (!session) {
      window.location.replace('/login');
      return null;
    }

    const profile = await getProfile();

    if (!profile || profile.is_active !== true) {
      await sb().auth.signOut();
      window.location.replace('/login');
      return null;
    }

    if (
      opts.roles &&
      !opts.roles.includes(profile.role)
    ) {
      window.location.replace('/dashboard');
      return null;
    }

    return profile;
  }

  async function login(email, password) {
    const client = sb();

    const { data, error } = await withTimeout(
      client.auth.signInWithPassword({
        email: email.trim(),
        password
      }),
      'Login Supabase'
    );

    if (error) throw error;

    try {
      const { data: profile, error: profileError } =
        await withTimeout(
          client
            .from('profiles')
            .select('id, email, full_name, role, is_active')
            .eq('id', data.user.id)
            .single(),
          'Memuat profil'
        );

      if (profileError) throw profileError;

      if (!profile || profile.is_active !== true) {
        throw new Error(
          'Akun tidak aktif atau profil tidak ditemukan.'
        );
      }

      return { ...data, profile };

    } catch (error) {
      await client.auth.signOut();
      throw error;
    }
  }

  async function logout() {
    await sb().auth.signOut();
    window.location.replace('/login');
  }

  window.CVSAuth = {
    getSession,
    getProfile,
    requireAuth,
    login,
    logout
  };
})();

