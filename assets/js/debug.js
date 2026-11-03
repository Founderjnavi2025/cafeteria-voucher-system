
/**
 * CVS DEBUG TOOL
 * File: assets/js/debug.js
 * Tidak menampilkan password, access token, atau API key.
 */
(async function () {
  const PREFIX = '[CVS DEBUG]';

  const log = (label, data = '') => {
    console.log(`${PREFIX} ${label}`, data);
  };

  const fail = (label, error) => {
    console.error(`${PREFIX} ${label}`, {
      message: error?.message || String(error),
      code: error?.code || null,
      status: error?.status || null,
      details: error?.details || null,
      hint: error?.hint || null
    });
  };

  const result = {
    timestamp: new Date().toISOString(),
    url: location.href,
    checks: {}
  };

  function check(name, ok, detail = '') {
    result.checks[name] = { ok, detail };
    log(`${ok ? 'PASS' : 'FAIL'}: ${name}`, detail);
  }

  try {
    console.group('CVS SYSTEM DIAGNOSTIC');

    // 1. Periksa konfigurasi
    check(
      'CVS_CONFIG',
      !!window.CVS_CONFIG,
      window.CVS_CONFIG
        ? {
            version: window.CVS_CONFIG.APP_VERSION,
            supabaseUrlConfigured: !!window.CVS_CONFIG.SUPABASE_URL
          }
        : 'CVS_CONFIG tidak ditemukan'
    );

    // 2. Periksa library Supabase
    check(
      'SUPABASE_LIBRARY',
      !!window.supabase?.createClient,
      window.supabase ? 'Library tersedia' : 'Library belum dimuat'
    );

    // 3. Periksa Supabase client
    const client = window.cvsSupabase;

    check(
      'SUPABASE_CLIENT',
      !!client?.auth,
      client ? 'Client tersedia' : 'cvsSupabase tidak ditemukan'
    );

    if (!client?.auth) {
      console.error('CVS DEBUG dihentikan: Supabase client tidak tersedia.');
      console.groupEnd();
      return;
    }

    // 4. Periksa sesi
    try {
      const { data, error } = await client.auth.getSession();

      if (error) throw error;

      const session = data.session;

      check('AUTH_SESSION', !!session, session
        ? {
            userId: session.user.id,
            email: session.user.email,
            expiresAt: session.expires_at
          }
        : 'Belum login'
      );

      if (!session) {
        result.summary = 'Belum ada sesi login.';
        window.CVS_DEBUG_RESULT = result;
        console.log('HASIL DEBUG:', result);
        console.groupEnd();
        return;
      }

      // 5. Periksa profil
      try {
        const { data: profile, error: profileError } = await client
          .from('profiles')
          .select('id,email,full_name,role,is_active')
          .eq('id', session.user.id)
          .single();

        if (profileError) throw profileError;

        check('PROFILE_QUERY', !!profile, profile);

        check(
          'PROFILE_ACTIVE',
          profile?.is_active === true,
          profile?.is_active
        );

        check(
          'PROFILE_ROLE',
          ['admin', 'operator', 'viewer'].includes(profile?.role),
          profile?.role
        );

        // 6. Periksa RPC helper
        try {
          const { data: admin, error: adminError } =
            await client.rpc('is_admin');

          if (adminError) throw adminError;

          check('RPC_IS_ADMIN', true, admin);
        } catch (error) {
          check('RPC_IS_ADMIN', false, error.message);
          fail('RPC is_admin', error);
        }

      } catch (error) {
        check('PROFILE_QUERY', false, error.message);
        fail('PROFILE QUERY', error);
      }

    } catch (error) {
      check('AUTH_SESSION', false, error.message);
      fail('AUTH SESSION', error);
    }

    result.summary = 'Pemeriksaan selesai.';
    window.CVS_DEBUG_RESULT = result;

    console.log('HASIL DEBUG LENGKAP:', result);
    console.groupEnd();

  } catch (error) {
    fail('DEBUG FATAL', error);
    console.groupEnd();
  }
})();

