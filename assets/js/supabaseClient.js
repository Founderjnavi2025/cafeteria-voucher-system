/**
 * File: assets/js/supabaseClient.js
 * Inisialisasi Supabase client global (window.cvsSupabase).
 * Dimuat setelah config.js dan CDN Supabase.
 *
 * PENTING:
 * - File ini TIDAK menyimpan kredensial (URL/Key). Semua diambil dari config.js.
 * - Validasi hanya memastikan tidak masih placeholder ('YOUR_...').
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
  
  // Cek apakah URL masih placeholder atau kosong
  if (!cfg.SUPABASE_URL || cfg.SUPABASE_URL.indexOf('YOUR_') !== -1 || cfg.SUPABASE_URL.length < 10) {
    console.error('[CVS] SUPABASE_URL belum dikonfigurasi (masih placeholder atau kosong).');
    return;
  }
  
  // Cek apakah ANON KEY masih placeholder atau kosong
  if (!cfg.SUPABASE_ANON_KEY || cfg.SUPABASE_ANON_KEY.indexOf('YOUR_') !== -1 || cfg.SUPABASE_ANON_KEY.length < 20) {
    console.error('[CVS] SUPABASE_ANON_KEY belum dikonfigurasi (masih placeholder atau kosong).');
    return;
  }

  // Inisialisasi Client
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
  
  console.log('[CVS] Supabase client initialized for', cfg.SUPABASE_URL);
})();
