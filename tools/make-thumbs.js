#!/usr/bin/env node
/**
 * make-thumbs — renders a PNG thumbnail for every bundled model (kits/assets-core) with the dependency-free software
 * renderer (src/main/glbThumb.js): no Blender, no GPU. Run once after adding models; thumbnails are committed.
 *   node kits/tools/make-thumbs.js
 */
const fs = require('fs');
const path = require('path');
const { renderGlb } = require('../../src/main/glbThumb');
const core = path.join(__dirname, '..', 'assets-core');
const out = path.join(core, 'thumbs');
fs.mkdirSync(out, { recursive: true });
const idx = JSON.parse(fs.readFileSync(path.join(core, 'index.json'), 'utf-8'));
let ok = 0, bad = 0;
for (const e of idx.entries) {
  if (!/\.glb$/i.test(e.file || '')) continue;
  const dest = path.join(out, e.id.replace(/[^a-z0-9]+/gi, '_') + '.png');
  if (fs.existsSync(dest)) { ok++; continue; }
  try { fs.writeFileSync(dest, renderGlb(path.join(core, e.file)).png); ok++; } catch (err) { bad++; console.warn('skip', e.id, err.message); }
}
console.log(`thumbnails: ${ok} ok, ${bad} failed -> ${out}`);
