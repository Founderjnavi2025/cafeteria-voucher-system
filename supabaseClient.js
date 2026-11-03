/**
 * File: assets/js/supabaseClient.js
 * Inisialisasi Supabase client global (window.cvsSupabase).
 * Dimuat setelah config.js dan CDN Supabase.
 */
(function() {
  const cfg = window.CVS_CONFIG;
  if (!cfg) {
    console.error('[CVS] CVS_CONFIG tidak ditemukan. Pastikan config.js dimuat dulu.');
    return;
  }
  if (!window.supabase || !window.supabase.createClient) {
    console.error('[CVS] Supabase library belum dimuat dari CDN.');
    return;
  }
  if (!cfg.SUPABASE_URL || cfg.SUPABASE_URL.includes('YOUR_')) {
    console.error('[CVS] SUPABASE_URL belum dikonfigurasi.');
    return;
  }
  if (!cfg.SUPABASE_ANON_KEY || cfg.SUPABASE_ANON_KEY.includes('YOUR_')) {
    console.error('[CVS] SUPABASE_ANON_KEY belum dikonfigurasi.');
    return;
  }
  
  window.cvsSupabase = window.supabase.createClient(
    cfg.SUPABASE_URL,
    cfg.SUPABASE_ANON_KEY,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        storageKey: 'cvs-auth'
      }
    }
  );
})();
