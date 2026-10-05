#!/usr/bin/env node
/**
 * make-fallback-music — renders the kits' FALLBACK music library (the instant,
 * always-there music a game uses until its own tracks are rendered, and when the
 * synth isn't installed yet): one short original loop per mood, plus the stingers
 * and a musical pickup note — all composed by Playpen's composer and rendered with
 * the real General MIDI SoundFont (GeneralUser GS), never hand-coded tones.
 *
 *   node kits/tools/make-fallback-music.js           (needs FluidSynth + the SoundFont)
 *
 * Output: kits/common/audio/fallback/<mood>/*.ogg, audio/stingers/*.ogg, audio/sfx/pickup.ogg
 */
const fs = require('fs');
const path = require('path');
const compose = require('../../src/main/music/compose');
const render = require('../../src/main/music/render');

const OUT = path.join(__dirname, '..', 'common');
const MOODS = [
  { mood: 'sunny', key: 'C', instruments: ['steel_drum', 'ukulele', 'marimba', 'bass', 'light_drums'] },
  { mood: 'upbeat', key: 'G', instruments: ['electric_piano', 'clean_guitar', 'bass', 'light_drums'] },
  { mood: 'calm', key: 'D', instruments: ['flute', 'harp', 'warm_pad', 'acoustic_bass', 'soft_drums'] },
  { mood: 'adventurous', key: 'E', scale: 'lydian', instruments: ['flute', 'harp', 'strings', 'horn', 'soft_drums'] },
  { mood: 'tense', key: 'A', instruments: ['oboe', 'piano', 'slow_strings', 'bass'] },
  { mood: 'mysterious', key: 'A', scale: 'dorian', instruments: ['celesta', 'harp', 'halo_pad', 'bass'] },
  { mood: 'racing', key: 'E', instruments: ['saw_lead', 'overdrive_guitar', 'synth_strings', 'pick_bass'] }
];

async function main() {
  const tools = render.locateTools();
  if (!tools.ready) { console.error('FluidSynth + SoundFont not found (run the app once, or set PLAYPEN_FLUIDSYNTH / PLAYPEN_SOUNDFONT).'); process.exit(1); }
  const dir = path.join(OUT, 'audio');
  for (const m of MOODS) {
    const song = compose.composeSong({ title: `fallback-${m.mood}`, key: m.key, scale: m.scale, mood: m.mood, instruments: m.instruments, loopBars: 4, introBars: 0, seed: compose.hashSeed('fallback-' + m.mood) });
    delete song.variation;
    song.intro = [];
    const tmpProject = path.join(OUT, '.tmp-fallback', m.mood);
    await render.renderSong(song, { projectDir: tmpProject, trackId: m.mood, quality: 3, tools });
    const from = path.join(tmpProject, 'audio', 'music', m.mood);
    const to = path.join(dir, 'fallback', m.mood);
    fs.rmSync(to, { recursive: true, force: true });
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.renameSync(from, to);
    console.log(`fallback/${m.mood}: ${compose.MOODS[m.mood].scale} ${song.bpm} bpm in ${m.key}`);
  }
  fs.rmSync(path.join(OUT, '.tmp-fallback'), { recursive: true, force: true });
  for (const name of Object.keys(render.STINGERS)) {
    await render.renderStinger(name, { projectDir: OUT, key: 'C', tools });
    console.log(`stinger: ${name}`);
  }
  await render.renderPickupNote({ projectDir: OUT, tools });
  console.log('sfx/pickup.ogg (vibraphone C5)');
  // pickup.wav (synth) is superseded by the rendered note
  try { fs.unlinkSync(path.join(dir, 'sfx', 'pickup.wav')); } catch { /* not there */ }
}
if (require.main === module) main().catch((e) => { console.error(e.stack); process.exit(1); });
module.exports = { main, MOODS };
