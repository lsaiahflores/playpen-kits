#!/usr/bin/env node
/**
 * make-audio — generates the kits' sound-effect and ambience-bed WAVs
 * (kits/common/audio/{sfx,ambience}) with plain DSP, so they carry no licensing
 * baggage. MUSIC and stingers are NOT made here: they're composed as MIDI and
 * rendered with real instruments by Playpen's music pipeline (src/main/music).
 *
 *   node kits/tools/make-audio.js
 *
 * Deterministic (seeded) — re-running produces identical files.
 */
const fs = require('fs');
const path = require('path');
const { writeWav } = require('../../src/main/music/dsp');

const RATE = 22050;
const OUT = path.join(__dirname, '..', 'common', 'audio');

function rng(seed) { let s = seed >>> 0 || 1; return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296 * 2 - 1; }; }
const N = (sec) => Math.round(sec * RATE);

// one-pole filters
function lowpass(x, fc) { const a = 1 - Math.exp(-2 * Math.PI * fc / RATE); const y = new Float32Array(x.length); let s = 0; for (let i = 0; i < x.length; i++) { s += a * (x[i] - s); y[i] = s; } return y; }
function highpass(x, fc) { const lp = lowpass(x, fc); return x.map((v, i) => v - lp[i]); }
function bandpass(x, lo, hi) { return lowpass(highpass(x, lo), hi); }
function noise(n, seed) { const r = rng(seed); const o = new Float32Array(n); for (let i = 0; i < n; i++) o[i] = r(); return o; }
function norm(x, peak = 0.9) { let m = 1e-9; for (const v of x) m = Math.max(m, Math.abs(v)); return x.map((v) => v / m * peak); }
function mix(...xs) { const n = Math.max(...xs.map((x) => x.length)); const o = new Float32Array(n); for (const x of xs) for (let i = 0; i < x.length; i++) o[i] += x[i]; return o; }
function scale(x, g) { return x.map((v) => v * g); }
function env(n, a, d, sus = 0, decayPow = 2) { const o = new Float32Array(n); const an = N(a); for (let i = 0; i < n; i++) o[i] = i < an ? i / an : Math.pow(Math.max(0, 1 - (i - an) / Math.max(1, N(d))), decayPow) * (1 - sus) + sus * (i < an + N(d) ? 1 : 0); return o; }
function tone(n, f, f2 = f, wave = 'sin') { const o = new Float32Array(n); let ph = 0; for (let i = 0; i < n; i++) { const f0 = f + (f2 - f) * i / n; ph += 2 * Math.PI * f0 / RATE; o[i] = wave === 'tri' ? 2 / Math.PI * Math.asin(Math.sin(ph)) : wave === 'sq' ? (Math.sin(ph) > 0 ? 0.6 : -0.6) : Math.sin(ph); } return o; }
function mul(a, b) { return a.map((v, i) => v * (b[i] === undefined ? 0 : b[i])); }
/** make a loop seamless: crossfade the last `xf` seconds into the first */
function seamless(x, xf = 0.8) { const k = N(xf); const n = x.length - k; const o = x.slice(0, n); for (let i = 0; i < k; i++) { const t = i / k; o[i] = x[i] * t + x[n + i] * (1 - t); } return o; }
function save(folder, name, x, peak = 0.85) { const dir = path.join(OUT, folder); fs.mkdirSync(dir, { recursive: true }); fs.writeFileSync(path.join(dir, name + '.wav'), writeWav([norm(x, peak)], RATE)); }

// ---------------------------------------------------------------- ambience beds (seamless loops)
function windBed() { const n = N(12); const base = bandpass(noise(n, 11), 120, 1400); const lfo = new Float32Array(n); for (let i = 0; i < n; i++) lfo[i] = 0.5 + 0.35 * Math.sin(2 * Math.PI * i / RATE / 6.0) + 0.15 * Math.sin(2 * Math.PI * i / RATE / 2.3 + 1); return seamless(mul(base, lfo)); }
function wavesBed() { const n = N(14); const hiss = bandpass(noise(n, 21), 400, 3500); const rum = lowpass(noise(n, 22), 260); const o = new Float32Array(n); for (let i = 0; i < n; i++) { const t = i / RATE; const swell = Math.pow(0.5 + 0.5 * Math.sin(2 * Math.PI * t / 7.0 - 1.2), 2.2); const swell2 = Math.pow(0.5 + 0.5 * Math.sin(2 * Math.PI * t / 4.6 + 0.6), 3); o[i] = rum[i] * (0.4 + 0.9 * swell) + hiss[i] * (0.08 + 0.55 * swell2 * swell); } return seamless(o); }
function chirp(n, start, dur, f0, f1, seed, amp = 1) { const o = new Float32Array(n); const s0 = N(start); const L = N(dur); let ph = 0; for (let i = 0; i < L && s0 + i < n; i++) { const t = i / L; const f = f0 + (f1 - f0) * t + 60 * Math.sin(t * 40); ph += 2 * Math.PI * f / RATE; const e = Math.sin(Math.PI * t); o[s0 + i] = (Math.sin(ph) + 0.35 * Math.sin(2 * ph)) * e * e * amp; } return o; }
function gullsBed() { const n = N(14); const w = scale(windBed().slice(0, n), 0.35); const r = rng(31); const g = new Float32Array(n); for (const t of [1.2, 1.5, 5.4, 5.7, 6.1, 9.8, 11.5]) { const base = 1500 + 400 * (r() + 1); g.set(mix(g, chirp(n, t, 0.34, base, base * 1.5, 1, 0.5), chirp(n, t + 0.34, 0.3, base * 1.4, base * 0.9, 2, 0.4)), 0); } return seamless(mix(w, scale(g, 0.7))); }
function cityBed() { const n = N(16); const rum = lowpass(noise(n, 41), 180); const hum = tone(n, 62, 62); const o = new Float32Array(n); const pass = (start, dur, dir) => { const s0 = N(start); const L = N(dur); const nz = bandpass(noise(L, 50 + start), 200, 1800); for (let i = 0; i < L; i++) { const t = i / L; const g = Math.pow(Math.sin(Math.PI * t), 2) * 0.5; o[s0 + i] += nz[i] * g * (0.6 + 0.4 * (dir > 0 ? t : 1 - t)); } }; pass(2.0, 3.2, 1); pass(7.5, 3.6, -1); pass(12.0, 2.8, 1); const dist = scale(bandpass(noise(n, 43), 600, 2400), 0.05); for (let i = 0; i < n; i++) o[i] += rum[i] * 0.9 + hum[i] * 0.05 + dist[i]; return seamless(o); }
function forestBed() { const n = N(14); const wind = scale(windBed().slice(0, n), 0.3); const bird = new Float32Array(n); const r = rng(61); for (let k = 0; k < 9; k++) { const t = 0.5 + k * 1.45 + (r() + 1) * 0.3; const f = 2400 + (r() + 1) * 700; for (let j = 0; j < 3; j++) bird.set(mix(bird, chirp(n, t + j * 0.16, 0.12, f, f * (j % 2 ? 0.8 : 1.3), 3, 0.5)), 0); } return seamless(mix(wind, scale(bird, 0.55))); }
function cricketsBed() { const n = N(10); const o = new Float32Array(n); for (let i = 0; i < n; i++) { const t = i / RATE; const burst = Math.max(0, Math.sin(2 * Math.PI * t * 2.1)); const pulses = Math.max(0, Math.sin(2 * Math.PI * t * 28)); o[i] = Math.sin(2 * Math.PI * 4300 * t) * burst * pulses * 0.5 + Math.sin(2 * Math.PI * 4050 * t + 1) * Math.max(0, Math.sin(2 * Math.PI * t * 1.7 + 2)) * Math.max(0, Math.sin(2 * Math.PI * t * 24)) * 0.35; } return seamless(mix(o, scale(lowpass(noise(n, 71), 500), 0.05)), 0.5); }

// ---------------------------------------------------------------- sfx
function step(kind) {
  const n = N(0.16);
  let x;
  switch (kind) {
    case 'grass': x = scale(bandpass(noise(n, 81), 300, 2200), 0.8); return mul(x, env(n, 0.004, 0.14, 0, 2.5));
    case 'sand': x = bandpass(noise(n, 82), 200, 1800); return mul(x, env(n, 0.012, 0.15, 0, 2));
    case 'wood': x = mix(scale(tone(n, 190, 150), 0.7), scale(bandpass(noise(n, 83), 400, 2500), 0.4)); return mul(x, env(n, 0.002, 0.12, 0, 3));
    case 'stone': x = mix(scale(tone(n, 320, 260), 0.35), scale(highpass(noise(n, 84), 1200), 0.5)); return mul(x, env(n, 0.001, 0.09, 0, 3));
    default: x = mix(scale(highpass(noise(n, 85), 1500), 0.7), scale(tone(n, 240, 170), 0.35)); return mul(x, env(n, 0.001, 0.07, 0, 3.5)); // pavement
  }
}
const sfx = {
  jump: () => { const n = N(0.22); return mul(mix(tone(n, 300, 640, 'tri'), scale(tone(n, 600, 1280), 0.15)), env(n, 0.005, 0.2, 0, 1.5)); },
  respawn: () => { const n = N(0.7); let x = new Float32Array(n); [523, 659, 784, 1047].forEach((f, i) => { const t = tone(n, f, f); const e = new Float32Array(n); for (let k = 0; k < n; k++) { const tt = k / RATE - i * 0.09; e[k] = tt > 0 ? Math.exp(-tt * 6) : 0; } x = mix(x, mul(t, e)); }); return x; },
  pickup: () => { const n = N(0.45); const t = mix(tone(n, 1047, 1047), scale(tone(n, 2093, 2093), 0.3)); return mul(t, env(n, 0.002, 0.43, 0, 2.2)); },
  swing: () => { const n = N(0.28); const nz = bandpass(noise(n, 91), 500, 5000); const e = new Float32Array(n); for (let i = 0; i < n; i++) e[i] = Math.pow(Math.sin(Math.PI * i / n), 1.5); return mul(nz, e); },
  hit: () => { const n = N(0.25); return mul(mix(tone(n, 160, 55), scale(bandpass(noise(n, 92), 300, 3000), 0.6)), env(n, 0.001, 0.22, 0, 3)); },
  hurt: () => { const n = N(0.35); return mul(mix(tone(n, 420, 180, 'sq'), scale(bandpass(noise(n, 93), 300, 2000), 0.3)), env(n, 0.003, 0.33, 0, 2)); },
  roll: () => { const n = N(0.4); const nz = bandpass(noise(n, 94), 150, 1500); const e = new Float32Array(n); for (let i = 0; i < n; i++) e[i] = Math.sin(Math.PI * i / n); return mul(nz, e); },
  block: () => { const n = N(0.3); return mul(mix(tone(n, 1250, 1180), scale(tone(n, 1870, 1800), 0.5), scale(highpass(noise(n, 95), 2500), 0.4)), env(n, 0.001, 0.28, 0, 3)); },
  interact: () => { const n = N(0.3); return mix(mul(tone(N(0.14), 660, 660), env(N(0.14), 0.003, 0.12, 0, 2)), (() => { const o = new Float32Array(n); mul(tone(N(0.16), 880, 880), env(N(0.16), 0.003, 0.14, 0, 2)).forEach((v, i) => { o[i + N(0.12)] = v; }); return o; })()); },
  defeat: () => { const n = N(0.5); return mul(mix(tone(n, 500, 120, 'tri'), scale(bandpass(noise(n, 96), 400, 2500), 0.35)), env(n, 0.002, 0.48, 0, 1.6)); },
  boost: () => { const n = N(0.6); const nz = bandpass(noise(n, 97), 600, 6000); const e = new Float32Array(n); for (let i = 0; i < n; i++) e[i] = Math.pow(i / n, 0.7) * Math.pow(1 - i / n, 0.6) * 3; return mix(mul(nz, e), mul(tone(n, 180, 720, 'tri'), scale(e, 0.4))); },
  count: () => { const n = N(0.22); return mul(tone(n, 880, 880), env(n, 0.002, 0.2, 0, 1.4)); },
  ui_click: () => { const n = N(0.07); return mul(mix(tone(n, 1400, 1100), scale(highpass(noise(n, 98), 3000), 0.15)), env(n, 0.001, 0.06, 0, 3)); },
  ui_hover: () => { const n = N(0.05); return mul(tone(n, 900, 1000), env(n, 0.002, 0.045, 0, 2)); },
  ui_confirm: () => { const n = N(0.3); return mix(mul(tone(N(0.12), 660, 660), env(N(0.12), 0.002, 0.1, 0, 2)), (() => { const o = new Float32Array(n); mul(tone(N(0.18), 990, 990), env(N(0.18), 0.002, 0.16, 0, 2)).forEach((v, i) => { o[i + N(0.1)] = v; }); return o; })()); }
};

// ---------------------------------------------------------------- LIVING-WORLD ambience beds (Batch 5): matched to the living-world layer
// (src/main/richWorld.js LIFE_SOUND). All seamless loops, plain DSP, deterministic. Written WITHOUT wiping the other audio.
function songbirdPhrase(n, t, base, seed, r) { const o = new Float32Array(n); const notes = 3 + Math.floor((r() + 1) * 2.5); for (let j = 0; j < notes; j++) { const f = base * (1 + 0.25 * Math.sin(j * 1.7 + seed) + (r() + 1) * 0.12); o.set(mix(o, chirp(n, t + j * 0.13, 0.1, f, f * (j % 2 ? 0.78 : 1.35), seed, 0.5)), 0); } return o; }
function birdsDayBed() { const n = N(16); const bird = new Float32Array(n); const r = rng(101); for (let k = 0; k < 14; k++) { const t = 0.3 + k * 1.1 + (r() + 1) * 0.35; bird.set(mix(bird, songbirdPhrase(n, t, 2300 + (r() + 1) * 900, k + 3, r)), 0); } const w = scale(windBed().slice(0, n), 0.18); return seamless(mix(w, scale(bird, 0.6))); }
function insectsDayBed() { const n = N(12); const o = new Float32Array(n); const buzz = bandpass(noise(n, 111), 3200, 6200); const bee = new Float32Array(n); for (let i = 0; i < n; i++) { const t = i / RATE; const pulse = 0.55 + 0.45 * Math.sin(2 * Math.PI * t * 0.35 + 1); o[i] = buzz[i] * (0.5 + 0.5 * Math.max(0, Math.sin(2 * Math.PI * t * 70))) * pulse * 0.5; bee[i] = Math.sin(2 * Math.PI * (190 + 12 * Math.sin(t * 3)) * t) * Math.max(0, Math.sin(2 * Math.PI * t * 0.23 + 2)) * 0.18; } return seamless(mix(o, bee, scale(windBed().slice(0, n), 0.12)), 0.6); }
function nightWindBed() { const n = N(14); return seamless(mix(scale(lowpass(windBed().slice(0, n), 500), 0.9), scale(bandpass(noise(n, 121), 80, 260), 0.35))); }
function owlNightBed() { const n = N(16); const o = new Float32Array(n); for (const t of [2.2, 9.5]) { for (let j = 0; j < 4; j++) { const L = j === 3 ? 0.7 : 0.28; const tt = t + j * 0.42 + (j === 3 ? 0.1 : 0); const len = N(L); const s0 = N(tt); for (let i = 0; i < len && s0 + i < n; i++) { const u = i / len; const f = 355 - 28 * u; const e = Math.pow(Math.sin(Math.PI * Math.min(1, u * 1.1)), 1.4); o[s0 + i] += (Math.sin(2 * Math.PI * f * (i / RATE)) + 0.3 * Math.sin(4 * Math.PI * f * (i / RATE))) * e * 0.5; } } } return seamless(mix(o, scale(nightWindBed(), 0.4), scale(cricketsBed().slice(0, n), 0.18)), 0.7); }
function rainBed() { const n = N(12); const hiss = bandpass(noise(n, 131), 1500, 9000); const body = lowpass(noise(n, 132), 1400); const drops = new Float32Array(n); const r = rng(133); for (let k = 0; k < 220; k++) { const t = N(((r() + 1) / 2) * 11.7); const len = N(0.012); for (let i = 0; i < len && t + i < n; i++) drops[t + i] += (r() * 0.7) * Math.exp(-i / (len * 0.25)); } return seamless(mix(scale(hiss, 0.55), scale(body, 0.35), scale(highpass(drops, 1800), 0.6)), 0.6); }
function rustleBed() { const n = N(12); const nz = bandpass(noise(n, 141), 1800, 7000); const o = new Float32Array(n); const g = rng(142); let gate = 0, tgt = 0; for (let i = 0; i < n; i++) { if (i % 1500 === 0) tgt = Math.max(0, g() + 0.15); gate += (tgt - gate) * 0.004; o[i] = nz[i] * gate * 0.8; } return seamless(mix(o, scale(windBed().slice(0, n), 0.25)), 0.6); }
function waterBed() { const n = N(12); const a = bandpass(noise(n, 151), 400, 2600); const b = bandpass(noise(n, 152), 900, 4200); const o = new Float32Array(n); for (let i = 0; i < n; i++) { const t = i / RATE; o[i] = a[i] * (0.6 + 0.4 * Math.sin(2 * Math.PI * t * 1.7)) + b[i] * (0.5 + 0.5 * Math.sin(2 * Math.PI * t * 3.1 + 1)) * 0.6; } return seamless(mix(o, scale(lowpass(noise(n, 153), 300), 0.4)), 0.6); }
function frogsBed() { const n = N(14); const o = new Float32Array(n); const r = rng(161); for (let k = 0; k < 16; k++) { const t = N(0.5 + k * 0.85 + (r() + 1) * 0.3); const f = 210 + (r() + 1) * 90; for (let j = 0; j < 3; j++) { const s0 = t + j * N(0.09); const len = N(0.07); for (let i = 0; i < len && s0 + i < n; i++) { const u = i / len; o[s0 + i] += (Math.sin(2 * Math.PI * f * (i / RATE) * (1 + 0.25 * u)) + 0.5 * Math.sin(2 * Math.PI * f * 2.1 * (i / RATE))) * Math.sin(Math.PI * u) * 0.4; } } } return seamless(mix(o, scale(cricketsBed().slice(0, n), 0.3), scale(nightWindBed(), 0.2)), 0.6); }
function beesBed() { const n = N(10); const o = new Float32Array(n); for (let i = 0; i < n; i++) { const t = i / RATE; const f = 205 + 25 * Math.sin(t * 2.3) + 10 * Math.sin(t * 17); o[i] = (Math.sin(2 * Math.PI * f * t) + 0.5 * Math.sin(4 * Math.PI * f * t)) * (0.5 + 0.5 * Math.sin(2 * Math.PI * t * 0.4)) * 0.3; } return seamless(mix(o, scale(bandpass(noise(n, 171), 150, 900), 0.12)), 0.5); }
function batBed() { const n = N(10); const o = new Float32Array(n); const r = rng(181); for (let k = 0; k < 12; k++) { const t = N(0.3 + k * 0.8 + (r() + 1) * 0.3); const len = N(0.18); for (let i = 0; i < len && t + i < n; i++) { const u = i / len; const flap = Math.max(0, Math.sin(2 * Math.PI * 14 * (i / RATE))); o[t + i] += (r() * 0.5) * flap * Math.sin(Math.PI * u) * 0.5; } } for (const tt of [1.4, 4.2, 7.1]) o.set(mix(o, chirp(n, tt, 0.06, 7200, 5200, 4, 0.12)), 0); return seamless(mix(bandpass(o, 300, 2600), scale(nightWindBed(), 0.25)), 0.5); }
function coosBed(f0, seed) { const n = N(12); const o = new Float32Array(n); const r = rng(seed); for (let k = 0; k < 7; k++) { const t = N(0.5 + k * 1.6 + (r() + 1) * 0.4); for (let j = 0; j < 2; j++) { const s0 = t + j * N(0.28); const len = N(0.22); for (let i = 0; i < len && s0 + i < n; i++) { const u = i / len; o[s0 + i] += Math.sin(2 * Math.PI * (f0 + 40 * Math.sin(u * 9) - 60 * u) * (i / RATE)) * Math.pow(Math.sin(Math.PI * u), 1.2) * 0.45; } } } return seamless(mix(o, scale(windBed().slice(0, n), 0.15)), 0.6); }
function crowsBed() { const n = N(12); const o = new Float32Array(n); const r = rng(191); for (let k = 0; k < 5; k++) { const t = N(0.8 + k * 2.2 + (r() + 1) * 0.4); for (let j = 0; j < 2 + (k % 2); j++) { const s0 = t + j * N(0.34); const len = N(0.26); const nz = bandpass(noise(len, 192 + k * 7 + j), 600, 2400); for (let i = 0; i < len && s0 + i < n; i++) { const u = i / len; o[s0 + i] += (nz[i] * 0.9 + Math.sin(2 * Math.PI * (520 - 140 * u) * (i / RATE)) * 0.4) * Math.sin(Math.PI * u) * 0.5; } } } return seamless(mix(o, scale(windBed().slice(0, n), 0.2)), 0.6); }
function hawkBed() { const n = N(14); const o = new Float32Array(n); for (const t of [2.0, 8.5]) o.set(mix(o, chirp(n, t, 0.7, 3000, 1700, 5, 0.6), chirp(n, t + 0.8, 0.55, 2800, 1500, 6, 0.5)), 0); return seamless(mix(scale(o, 0.8), scale(windBed().slice(0, n), 0.35)), 0.7); }
const LIVING_BEDS = { birds_day: [birdsDayBed, 0.75], insects_day: [insectsDayBed, 0.7], crickets_night: [() => cricketsBed(), 0.7], night_wind: [nightWindBed, 0.65], owl_night: [owlNightBed, 0.75], rain: [rainBed, 0.75], rustle: [rustleBed, 0.65], water: [waterBed, 0.7], frogs_night: [frogsBed, 0.7], bees: [beesBed, 0.6], bat_flutter: [batBed, 0.6], pigeons: [() => coosBed(330, 201), 0.65], crows: [crowsBed, 0.7], hawk_cry: [hawkBed, 0.7] };

function writeLivingBeds() {
  for (const [name, [fn, peak]] of Object.entries(LIVING_BEDS)) save('ambience', name, fn(), peak);
  return Object.keys(LIVING_BEDS);
}

function main() {
  if (process.argv.includes('--living-only')) { const names = writeLivingBeds(); console.log('wrote ' + names.length + ' living-world ambience beds: ' + names.join(', ')); return; }
  fs.rmSync(OUT, { recursive: true, force: true });
  save('ambience', 'wind', windBed(), 0.7);
  save('ambience', 'waves', wavesBed(), 0.8);
  save('ambience', 'gulls', gullsBed(), 0.8);
  save('ambience', 'city', cityBed(), 0.75);
  save('ambience', 'forest', forestBed(), 0.75);
  save('ambience', 'crickets', cricketsBed(), 0.7);
  writeLivingBeds();
  for (const k of ['grass', 'pavement', 'wood', 'sand', 'stone']) save('sfx', `step_${k}`, step(k), 0.75);
  for (const [name, fn] of Object.entries(sfx)) save('sfx', name, fn(), 0.85);
  const count = fs.readdirSync(path.join(OUT, 'sfx')).length + fs.readdirSync(path.join(OUT, 'ambience')).length;
  console.log(`wrote ${count} audio files to ${OUT}`);
}
if (require.main === module) main();
module.exports = { main, LIVING_BEDS, writeLivingBeds };
