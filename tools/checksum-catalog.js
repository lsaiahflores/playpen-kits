#!/usr/bin/env node
/**
 * checksum-catalog — records size + sha256 for catalog packs that are downloaded on demand from their ORIGINAL source
 * (large packs are never mirrored in the kits repo). Done in SMALL BATCHES so it never hammers a source:
 *
 *   node kits/tools/checksum-catalog.js --limit 10 [--source kenney] [--max-mb 120]
 *
 * Each run fills the next N entries that have a downloadUrl but no sha256. Entries over --max-mb are skipped (listed as
 * "large": source URL only, checksum added when they are fetched for real). At install time the catalog verifies the
 * archive against this checksum and refuses a mismatch.
 */
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const OUT = path.join(__dirname, '..', 'catalog', 'index.json');
const UA = { 'User-Agent': 'Mozilla/5.0 (Playpen catalog checksum)' };
const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };

async function hashUrl(url, maxBytes) {
  const r = await fetch(url, { headers: UA, redirect: 'follow' });
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  const len = Number(r.headers.get('content-length') || 0);
  if (len && len > maxBytes) return { large: true, bytes: len };
  const h = crypto.createHash('sha256');
  let bytes = 0;
  for await (const chunk of r.body) { h.update(chunk); bytes += chunk.length; if (bytes > maxBytes) return { large: true, bytes }; }
  return { sha256: h.digest('hex'), bytes };
}

(async () => {
  const limit = Number(arg('limit', 10)), maxBytes = Number(arg('max-mb', 120)) * 1024 * 1024, only = arg('source', null);
  const cat = JSON.parse(fs.readFileSync(OUT, 'utf-8'));
  const todo = cat.entries.filter((e) => /^https?:/.test(e.downloadUrl || '') && !e.sha256 && !e.large && (!only || e.source === only)).slice(0, limit);
  console.log(`checksumming ${todo.length} of ${cat.entries.filter((e) => /^https?:/.test(e.downloadUrl || '') && !e.sha256 && !e.large).length} remaining…`);
  for (const e of todo) {
    try {
      const r = await hashUrl(e.downloadUrl, maxBytes);
      if (r.large) { e.large = true; e.sizeBytes = r.bytes; console.log(`  ${e.id}: large (${(r.bytes / 1048576).toFixed(0)} MB) — source URL only`); }
      else { e.sha256 = r.sha256; e.sizeBytes = r.bytes; console.log(`  ${e.id}: ${(r.bytes / 1048576).toFixed(1)} MB ${r.sha256.slice(0, 12)}…`); }
    } catch (err) { console.warn(`  ${e.id}: ${err.message}`); }
  }
  fs.writeFileSync(OUT, JSON.stringify(cat, null, 1));
})();
