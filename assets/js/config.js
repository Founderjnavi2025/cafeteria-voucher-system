/**
 * File: assets/js/config.js
 *
 * PENTING:
 * - Hanya anon key yang boleh ada di sini. service_role DILARANG.
 * - Untuk deploy Vercel, isi window.__ENV__ dari env variable.
 * - Device ID adalah identifier, bukan autentikasi perangkat.
 */
window.CVS_CONFIG = {
  SUPABASE_URL: (window.__ENV__ && window.__ENV__.SUPABASE_URL) || 'YOUR_SUPABASE_URL',
  SUPABASE_ANON_KEY: (window.__ENV__ && window.__ENV__.SUPABASE_ANON_KEY) || 'YOUR_SUPABASE_ANON_KEY',
  APP_NAME: 'Cafeteria Voucher System',
  APP_VERSION: '1.0.0',
  DISPLAY_TIMEZONE: 'Asia/Jakarta',
  
  /**
   * Device ID disimpan di localStorage. Ini HANYA identifier kiosk,
   * BUKAN bukti bahwa request berasal dari perangkat resmi.
   * Gate keamanan sebenarnya adalah sesi login operator (Supabase Auth).
   */
  getDeviceId() {
    let id = localStorage.getItem('cvs_device_id');
    if (!id) {
      id = 'KIOSK-' + Math.random().toString(36).slice(2, 8).toUpperCase();
      localStorage.setItem('cvs_device_id', id);
    }
    return id;
  },
  setDeviceId(id) {
    if (!id || typeof id !== 'string' || id.length > 64) {
      throw new Error('Device ID tidak valid');
    }
    localStorage.setItem('cvs_device_id', id);
  }
};
