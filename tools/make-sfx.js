#!/usr/bin/env node
/**
 * make-sfx — builds the kit's SFX LIBRARY (Part 8): layered, varied, original sounds written as WAV files, indexed by event
 * and sound palette. Everything here is synthesized from scratch by this script (noise, filtered thumps, clicks, tails), so the
 * whole library is original work with no third-party licence to track; verified-CC0 packs (Kenney etc.) can be dropped into the
 * same folders later and win automatically (PNAudio prefers a real file).
 *
 *   audio/sfx/<palette>/<event>_<n>.wav     palettes: toy_plastic (clicky, bright, bouncy), scifi (punchy, electric)
 *
 * Weapon sounds are LAYERED: a mechanical click + a body + a tail. Each event has several variants.
 */
const fs = require('fs');
const path = require('path');
const RATE = 22050;
let seed = 12345;
const rnd = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 4294967296; };

function buf(sec) { return new Float32Array(Math.floor(RATE * sec)); }
function mix(dst, src, at = 0, gain = 1) { for (let i = 0; i < src.length && i + at < dst.length; i++) dst[i + at] += src[i] * gain; }
function lowpass(x, k) { let y = 0; return x.map((v) => (y += (v - y) * k)); }
function highpass(x, k) { const lp = lowpass(x, k); return x.map((v, i) => v - lp[i]); }
function noise(sec, decay) { const b = buf(sec); for (let i = 0; i < b.length; i++) b[i] = (rnd() * 2 - 1) * Math.exp(-(i / RATE) * decay); return b; }
function thump(sec, f0, f1, decay) { const b = buf(sec); let ph = 0; for (let i = 0; i < b.length; i++) { const t = i / RATE; const f = f1 + (f0 - f1) * Math.exp(-t * 28); ph += (2 * Math.PI * f) / RATE; b[i] = Math.sin(ph) * Math.exp(-t * decay); } return b; }
function tone(sec, f, decay, wave = 'sine', f2 = null) { const b = buf(sec); let ph = 0; for (let i = 0; i < b.length; i++) { const t = i / RATE; const ff = f2 ? f + (f2 - f) * (t / sec) : f; ph += (2 * Math.PI * ff) / RATE; const s = wave === 'square' ? Math.sign(Math.sin(ph)) * 0.6 : wave === 'saw' ? ((ph / (2 * Math.PI)) % 1) * 2 - 1 : Math.sin(ph); b[i] = s * Math.exp(-t * decay); } return b; }
function click(v) { const b = buf(0.02); for (let i = 0; i < b.length; i++) b[i] = (rnd() * 2 - 1) * Math.exp(-i / (RATE * 0.002)) * v; return b; }
function norm(b, peak = 0.9) { let m = 0; for (const v of b) m = Math.max(m, Math.abs(v)); const g = m > 0 ? peak / m : 1; return b.map((v) => v * g); }

function wav(samples) {
  const n = samples.length; const out = Buffer.alloc(44 + n * 2);
  out.write('RIFF', 0); out.writeUInt32LE(36 + n * 2, 4); out.write('WAVEfmt ', 8); out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(RATE, 24); out.writeUInt32LE(RATE * 2, 28); out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34); out.write('data', 36); out.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) out.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(samples[i] * 32767))), 44 + i * 2);
  return out;
}

// palette flavors: brightness of the body, click prominence, tail length
const PAL = {
  toy_plastic: { body: 0.55, click: 1.4, tail: 0.6, pitch: 1.25, tone: 'sine' },
  scifi: { body: 0.35, click: 0.8, tail: 1.0, pitch: 0.9, tone: 'saw' }
};

const EVENTS = {
  shot_rifle: (p) => { const b = buf(0.45); mix(b, click(p.click), 0, 0.8); mix(b, lowpass(noise(0.18, 22), p.body), 0, 0.9); mix(b, thump(0.2, 220 * p.pitch, 90, 20), 0, 0.9); mix(b, lowpass(noise(0.4, 9), 0.12), 600, 0.25 * p.tail); return b; },
  shot_pistol: (p) => { const b = buf(0.4); mix(b, click(p.click), 0, 1); mix(b, lowpass(noise(0.12, 30), p.body + 0.1), 0, 0.8); mix(b, thump(0.14, 300 * p.pitch, 130, 26), 0, 0.8); mix(b, lowpass(noise(0.3, 12), 0.1), 400, 0.22 * p.tail); return b; },
  shot_shotgun: (p) => { const b = buf(0.6); mix(b, click(p.click), 0, 0.9); mix(b, lowpass(noise(0.3, 12), p.body), 0, 1.0); mix(b, thump(0.3, 150 * p.pitch, 55, 12), 0, 1.0); mix(b, lowpass(noise(0.5, 6), 0.08), 900, 0.35 * p.tail); return b; },
  launcher: (p) => { const b = buf(0.7); mix(b, tone(0.45, 520 * p.pitch, 4, p.tone, 120), 0, 0.5); mix(b, lowpass(noise(0.5, 6), 0.2), 0, 0.7); mix(b, thump(0.3, 120, 50, 9), 0, 0.8); return b; },
  explosion: (p) => { const b = buf(1.4); mix(b, lowpass(noise(1.2, 3.2), 0.14), 0, 1.0); mix(b, thump(0.9, 90, 38, 4.2), 0, 1.0); mix(b, click(1.2), 0, 0.6); mix(b, lowpass(noise(1.2, 2), 0.05), 3000, 0.3 * p.tail); return b; },
  impact_brick: (p) => { const b = buf(0.18); mix(b, click(p.click), 0, 0.9); mix(b, highpass(noise(0.1, 40), 0.2), 0, 0.5); mix(b, tone(0.12, 900 * p.pitch + rnd() * 400, 45, 'sine'), 0, 0.5); return b; },
  impact_flesh: (p) => { const b = buf(0.2); mix(b, lowpass(noise(0.12, 30), 0.25), 0, 0.8); mix(b, thump(0.14, 160, 90, 28), 0, 0.8); return b; },
  hit_marker: (p) => { const b = buf(0.12); mix(b, tone(0.1, 1400 * p.pitch, 35, 'sine'), 0, 0.7); mix(b, click(0.8), 0, 0.5); return b; },
  hurt: (p) => { const b = buf(0.3); mix(b, tone(0.25, 340 * p.pitch, 9, p.tone, 180), 0, 0.5); mix(b, lowpass(noise(0.2, 18), 0.3), 0, 0.4); return b; },
  reload: (p) => { const b = buf(0.8); mix(b, click(1.2 * p.click), 0, 0.8); mix(b, tone(0.05, 700, 80, 'square'), 3000, 0.4); mix(b, click(1.4 * p.click), 7000, 0.9); mix(b, tone(0.06, 500, 70, 'square'), 9500, 0.4); return b; },
  weapon_swap: (p) => { const b = buf(0.25); mix(b, click(p.click), 0, 0.8); mix(b, tone(0.12, 480 * p.pitch, 25, 'sine', 700), 400, 0.35); return b; },
  jump: (p) => { const b = buf(0.22); mix(b, tone(0.2, 260 * p.pitch, 8, 'sine', 520), 0, 0.5); mix(b, lowpass(noise(0.1, 30), 0.3), 0, 0.25); return b; },
  land: (p) => { const b = buf(0.2); mix(b, thump(0.18, 140, 70, 22), 0, 0.8); mix(b, lowpass(noise(0.1, 30), 0.3), 0, 0.4); return b; },
  step_brick: (p) => { const b = buf(0.12); mix(b, click(p.click * 0.8), 0, 0.7); mix(b, thump(0.1, 180 + rnd() * 40, 100, 40), 0, 0.5); return b; },
  step_grass: (p) => { const b = buf(0.14); mix(b, lowpass(noise(0.12, 28), 0.2), 0, 0.5); return b; },
  pickup: (p) => { const b = buf(0.35); mix(b, tone(0.25, 880 * p.pitch, 8, 'sine'), 0, 0.5); mix(b, tone(0.25, 1320 * p.pitch, 9, 'sine'), 2200, 0.4); return b; },
  ui_confirm: (p) => { const b = buf(0.18); mix(b, tone(0.14, 660 * p.pitch, 14, 'sine', 990), 0, 0.5); return b; },
  ui_move: (p) => { const b = buf(0.08); mix(b, tone(0.06, 520 * p.pitch, 40, 'sine'), 0, 0.4); return b; },
  kill: (p) => { const b = buf(0.5); mix(b, tone(0.12, 784, 14, 'sine'), 0, 0.5); mix(b, tone(0.12, 988, 14, 'sine'), 2400, 0.5); mix(b, tone(0.3, 1319, 8, 'sine'), 4800, 0.5); return b; }
};
const VARIANTS = 4;

function build(outDir) {
  const index = { palettes: {}, events: Object.keys(EVENTS), variants: VARIANTS, note: 'Original, synthesized by tools/make-sfx.js. Real CC0 files placed in the same folders override these.' };
  for (const [pal, cfg] of Object.entries(PAL)) {
    const dir = path.join(outDir, pal);
    fs.mkdirSync(dir, { recursive: true });
    index.palettes[pal] = [];
    for (const [ev, fn] of Object.entries(EVENTS)) {
      for (let v = 1; v <= VARIANTS; v++) {
        seed = (ev.length * 977 + v * 7919 + pal.length * 31) >>> 0;
        const p = { ...cfg, pitch: cfg.pitch * (0.92 + rnd() * 0.16), click: cfg.click * (0.9 + rnd() * 0.2) };
        const s = norm(fn(p), ev.startsWith('step') || ev.startsWith('ui') ? 0.5 : 0.85);
        fs.writeFileSync(path.join(dir, `${ev}_${v}.wav`), wav(s));
        index.palettes[pal].push(`${ev}_${v}.wav`);
      }
    }
  }
  fs.writeFileSync(path.join(outDir, 'index.json'), JSON.stringify(index, null, 2));
  return index;
}

module.exports = { build, EVENTS, PAL };
if (require.main === module) {
  const out = process.argv[2] || path.join(__dirname, '..', 'common', 'audio', 'sfx');
  const idx = build(out);
  console.log(`wrote ${Object.values(idx.palettes).reduce((a, l) => a + l.length, 0)} sounds to ${out}`);
}
