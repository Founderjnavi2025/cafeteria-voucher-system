/**
 * File: assets/js/utils.js
 * CSV parser RFC 4180 + validasi malformed.
 *
 * Kebijakan kolom kurang: diisi '' (bukan malformed).
 * Kebijakan kolom lebih: malformed (ditolak).
 */
(function () {

  function parseCSV(text, opts = {}) {
    if (typeof text !== 'string') throw new Error('CSV: bukan string');
    if (text.charCodeAt(0) === 0xFEFF) text = text.slice(1);

    const delim = opts.delimiter || ',';
    const rows = [];
    let row = [];
    let field = '';
    let inQuotes = false;
    let afterQuote = false;
    let i = 0;
    const n = text.length;

    function endField() { row.push(field); field = ''; afterQuote = false; }
    function endRow() {
      if (row.length === 1 && row[0] === '' && !afterQuote) { row = []; return; }
      rows.push(row); row = [];
    }

    while (i < n) {
      const c = text[i];

      if (inQuotes) {
        if (c === '"') {
          if (i + 1 < n && text[i + 1] === '"') { field += '"'; i += 2; continue; }
          inQuotes = false; afterQuote = true; i++; continue;
        }
        field += c; i++; continue;
      }

      if (afterQuote) {
        if (c === delim) { endField(); i++; continue; }
        if (c === '\n') { endField(); endRow(); i++; continue; }
        if (c === '\r') {
          if (i + 1 < n && text[i + 1] === '\n') i++;
          endField(); endRow(); i++; continue;
        }
        if (c === ' ' || c === '\t') { i++; continue; }
        throw new Error('CSV: karakter tidak sah setelah closing quote di posisi ' + i);
      }

      if (c === '"') {
        if (field !== '') throw new Error('CSV: quote di tengah field di posisi ' + i);
        inQuotes = true; i++; continue;
      }

      if (c === delim) { endField(); i++; continue; }
      if (c === '\r') {
        if (i + 1 < n && text[i + 1] === '\n') i++;
        endField(); endRow(); i++; continue;
      }
      if (c === '\n') { endField(); endRow(); i++; continue; }

      field += c; i++;
    }

    if (inQuotes) throw new Error('CSV: quote tidak ditutup');
    if (field !== '' || row.length > 0 || afterQuote) { endField(); endRow(); }

    if (rows.length === 0) return [];

    const headers = rows[0].map(h => h.trim());
    if (headers.some(h => h === '')) throw new Error('CSV: header kosong');
    const seen = new Set();
    for (const h of headers) {
      if (seen.has(h)) throw new Error('CSV: header duplikat "' + h + '"');
      seen.add(h);
    }

    const out = [];
    for (let r = 1; r < rows.length; r++) {
      const raw = rows[r];
      if (raw.every(v => v === '')) continue;
      if (raw.length > headers.length) {
        throw new Error('CSV: baris ' + (r + 1) + ' punya ' + raw.length +
                        ' kolom, header ' + headers.length);
      }
      const obj = {};
      for (let c = 0; c < headers.length; c++) {
        obj[headers[c]] = raw[c] !== undefined ? raw[c].trim() : '';
      }
      out.push(obj);
    }
    return out;
  }

  function todayISO(tz = null) {
    const d = new Date();
    if (tz) return new Intl.DateTimeFormat('en-CA', { timeZone: tz }).format(d);
    const off = d.getTimezoneOffset();
    return new Date(d.getTime() - off * 60000).toISOString().slice(0, 10);
  }

  function todayLocalInputDate() {
    const d = new Date();
    const yyyy = d.getFullYear();
    const mm = String(d.getMonth() + 1).padStart(2, '0');
    const dd = String(d.getDate()).padStart(2, '0');
    return yyyy + '-' + mm + '-' + dd;
  }

  window.CVSUtils = { parseCSV, todayISO, todayLocalInputDate };
})();