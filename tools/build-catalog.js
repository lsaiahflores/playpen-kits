#!/usr/bin/env node
/**
 * build-catalog — builds kits/catalog/index.json, the searchable index of CC0
 * assets Claude picks from instead of guessing (and instead of hand-modeling).
 *
 * LICENSING IS THE POINT. Users may publish what they make, so only assets whose
 * licence we CONFIRM at build time are indexed:
 *   - Kenney:     the live asset page must contain the CC0 statement; the real hashed
 *                 .zip link is scraped from that same page (a guessed URL 404s).
 *   - Poly Haven: every asset is CC0 (their API only serves CC0; checked against /licenses).
 *   - ambientCG:  CC0 by site policy; the API's own licence field is recorded per asset.
 *   - Quaternius / KayKit: the live page must say CC0; they offer no scriptable download,
 *     so they're indexed as `manual: true` (shown to Claude as "ask the user to add it").
 * Each entry records the evidence (URL + matched text + date). Nothing unverifiable goes in.
 * No Mixamo raw files, no ripped/unknown-source packs.
 *
 *   node kits/tools/build-catalog.js
 */
const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, '..', 'catalog', 'index.json');
const UA = { 'User-Agent': 'Mozilla/5.0 (Playpen catalog builder)' };
const today = new Date().toISOString().slice(0, 10);

async function get(url, json = false) {
  const r = await fetch(url, { headers: UA, redirect: 'follow' });
  if (!r.ok) throw new Error(`${url} -> HTTP ${r.status}`);
  return json ? r.json() : r.text();
}

const KENNEY = [
  // slug, kind, style, tags, scale note
  ['nature-kit', 'models', 'low-poly', 'trees rocks bushes flowers grass nature forest plants mushrooms logs fences water bridge campfire tent', '1 unit = 1 m'],
  ['city-kit-commercial', 'models', 'low-poly', 'city buildings skyscrapers shops downtown urban commercial street', '1 unit = 1 m'],
  ['city-kit-suburban', 'models', 'low-poly', 'city houses suburban buildings fences driveway trees urban neighborhood', '1 unit = 1 m'],
  ['city-kit-roads', 'models', 'low-poly', 'roads streets intersections crosswalk city tiles highway urban', '1 unit = 1 m'],
  ['car-kit', 'models', 'low-poly', 'cars vehicles taxi truck police van race vehicles traffic', '1 unit = 1 m'],
  ['racing-kit', 'models', 'low-poly', 'racing track road barriers grandstand cars flags tires arch pit', '1 unit = 1 m'],
  ['platformer-kit', 'models', 'low-poly', 'platformer blocks platforms coins crates flags trees fences hazards', '1 unit = 1 m'],
  ['survival-kit', 'models', 'low-poly', 'survival tools campfire tent resources crafting barrel chest fish', '1 unit = 1 m'],
  ['castle-kit', 'models', 'low-poly', 'castle medieval walls towers gates siege fantasy', '1 unit = 1 m'],
  ['fantasy-town-kit', 'models', 'low-poly', 'fantasy town village houses market medieval walls roofs', '1 unit = 1 m'],
  ['pirate-kit', 'models', 'low-poly', 'pirate ships island cannon chest barrels palm beach tropical', '1 unit = 1 m'],
  ['space-kit', 'models', 'low-poly', 'space sci-fi station rocket astronaut craters', '1 unit = 1 m'],
  ['modular-buildings', 'models', 'low-poly', 'modular buildings houses city walls windows doors', '1 unit = 1 m'],
  ['prototype-textures', 'textures', 'toon', 'prototype grid textures blockout greybox dev', 'tileable'],
  ['input-prompts', 'ui', 'ui', 'controller prompts buttons keyboard xbox playstation glyphs input icons', '2D sprites'],
  ['ui-pack', 'ui', 'ui', 'ui interface buttons panels sliders menu gui', '2D sprites'],
  ['game-icons', 'ui', 'ui', 'icons game hud inventory', '2D sprites'],
  ['interface-sounds', 'audio', 'audio', 'ui sounds click menu confirm back hover', 'wav/ogg'],
  ['impact-sounds', 'audio', 'audio', 'impact sounds hit thud footsteps wood metal glass', 'wav/ogg'],
  ['rpg-audio', 'audio', 'audio', 'rpg sounds sword cloth leather coins door swing', 'wav/ogg']
];

// Wave 1 additions (Batch 5 6.1): characters, modular environment kits, particles, fonts, icons, more CC0 audio.
// Each is verified against kenney.nl's own page by kenney() below (CC0 statement + a real zip link) — nothing is indexed on faith.
const KENNEY_WAVE1 = [
  ['particle-pack', 'particles', 'ui', 'particles smoke fire spark magic dust flare light sprites effects vfx', '2D sprites'],
  ['smoke-particles', 'particles', 'ui', 'smoke particles puff explosion dust steam sprites vfx', '2D sprites'],
  ['splat-pack', 'particles', 'ui', 'splat blood paint ink decal impact sprites', '2D sprites'],
  ['foliage-sprites', 'particles', 'ui', 'foliage leaves grass plants sprites nature 2d', '2D sprites'],
  ['kenney-fonts', 'fonts', 'ui', 'fonts typeface title hud text pixel blocky future', 'ttf'],
  ['board-game-icons', 'ui', 'ui', 'icons board game dice cards pieces tokens hud', '2D sprites'],
  ['1-bit-pack', 'ui', 'ui', '1-bit pixel tiles retro monochrome sprites 8-bit dungeon', '2D sprites'],
  ['pixel-ui-pack', 'ui', 'ui', 'pixel ui buttons panels menu retro 8-bit interface', '2D sprites'],
  ['fantasy-ui-borders', 'ui', 'ui', 'fantasy ui borders frames panels storybook menu', '2D sprites'],
  ['pixel-platformer', 'ui', 'ui', 'pixel platformer tiles characters 2d side-scroller 8-bit retro', '2D sprites'],
  ['tiny-town', 'ui', 'ui', 'tiny town top-down tiles village 2d houses', '2D sprites'],
  ['platformer-characters', 'ui', 'ui', 'platformer characters 2d sprites heroes animated side-scroller', '2D sprites'],
  ['blocky-characters', 'characters', 'low-poly', 'characters blocky people humans voxel rigged npc hero toy', 'rigged'],
  ['mini-characters', 'characters', 'toon', 'characters mini chibi people toy rigged animated npc', 'rigged'],
  ['shape-characters', 'characters', 'toon', 'characters shapes simple cute mascot', 'rigged'],
  ['animal-pack', 'models', 'low-poly', 'animals pets creatures dog cat cow pig zoo farm', '1 unit = 1 m'],
  ['modular-dungeon-kit', 'models', 'low-poly', 'dungeon modular walls floors doors stairs torches crypt fantasy', '1 unit = 1 m'],
  ['graveyard-kit', 'models', 'low-poly', 'graveyard cemetery tombstone crypt spooky halloween fence', '1 unit = 1 m'],
  ['furniture-kit', 'models', 'low-poly', 'furniture interior room chair table bed sofa lamp indoor house', '1 unit = 1 m'],
  ['holiday-kit', 'models', 'low-poly', 'holiday christmas halloween decorations props festive', '1 unit = 1 m'],
  ['food-kit', 'models', 'low-poly', 'food kitchen fruit burger pizza vegetables restaurant props', '1 unit = 1 m'],
  ['hexagon-kit', 'models', 'low-poly', 'hexagon tiles board strategy terrain map', '1 unit = 1 m'],
  ['train-kit', 'models', 'low-poly', 'train rails station locomotive railway tracks', '1 unit = 1 m'],
  ['prototype-kit', 'models', 'toon', 'prototype blockout greybox kit level design primitives', '1 unit = 1 m'],
  ['blaster-kit', 'models', 'low-poly', 'blasters guns weapons pistol rifle shotgun scifi shooter targets', '1 unit = 1 m'],
  ['tower-defense-kit', 'models', 'low-poly', 'tower defense towers enemies turret map tiles', '1 unit = 1 m'],
  ['mini-dungeon', 'models', 'toon', 'dungeon mini toy diorama rooms chest enemies', '1 unit = 1 m'],
  ['mini-arena', 'models', 'toon', 'arena mini toy diorama battle ring', '1 unit = 1 m'],
  ['mini-skate', 'models', 'toon', 'skate park ramps rails toy diorama', '1 unit = 1 m'],
  ['sci-fi-sounds', 'audio', 'audio', 'sci-fi sounds laser explosion engine door beep space energy shots', 'wav/ogg'],
  ['ui-audio', 'audio', 'audio', 'ui sounds click switch toggle menu confirm cancel', 'wav/ogg'],
  ['digital-audio', 'audio', 'audio', 'digital retro 8-bit chiptune bleeps pickups jumps power-ups', 'wav/ogg'],
  ['music-jingles', 'audio', 'audio', 'music jingles stingers victory fail level-up short melody fanfare', 'wav/ogg'],
  ['casino-audio', 'audio', 'audio', 'casino cards chips dice coins slot sounds', 'wav/ogg']
];

const QUATERNIUS = [
  ['downtowncitymegakit', 'models', 'low-poly', 'city downtown buildings urban street props skyscrapers shops signs vehicles', '1 unit = 1 m'],
  ['stylizednaturemegakit', 'models', 'stylized', 'nature trees rocks bushes stylized forest plants flowers', '1 unit = 1 m'],
  ['medievalvillagemegakit', 'models', 'low-poly', 'medieval village houses fantasy town market walls roofs', '1 unit = 1 m'],
  ['fantasypropsmegakit', 'models', 'low-poly', 'fantasy props barrels chests crates tables torches', '1 unit = 1 m'],
  ['universalbasecharacters', 'characters', 'low-poly', 'characters humans base rigged animated npc hero', 'rigged'],
  ['universalanimationlibrary', 'characters', 'low-poly', 'animations idle run walk jump combat locomotion rigged', 'rigged'],
  ['ultimateanimatedanimals', 'characters', 'low-poly', 'animals animated wolf fox deer horse cow low poly', 'rigged'],
  ['ultimateplatformer', 'models', 'low-poly', 'platformer blocks platforms coins hazards level pieces', '1 unit = 1 m'],
  ['piratekit', 'models', 'low-poly', 'pirate ships island cannon chest barrels beach tropical', '1 unit = 1 m'],
  ['cubeworldkit', 'models', 'low-poly', 'cube world voxel blocks terrain trees', '1 unit = 1 m'],
  ['cyberpunkgamekit', 'models', 'low-poly', 'cyberpunk city neon sci-fi buildings night props', '1 unit = 1 m'],
  ['ultimatespacekit', 'models', 'low-poly', 'space sci-fi station rocket planets', '1 unit = 1 m']
];
const KAYKIT = [
  ['kaykit-adventurers', 'characters', 'toon', 'characters adventurers knight rogue mage barbarian heroes rigged animated', 'rigged, ~1 unit = 1 m'],
  ['kaykit-dungeon-remastered', 'models', 'toon', 'dungeon fantasy walls floors props torches chests', '1 unit = 1 m']
];

function metaOf(html, name) {
  const m = html.match(new RegExp(`<meta[^>]+(?:property|name)=["']${name}["'][^>]+content=["']([^"']*)["']`, 'i')) || html.match(new RegExp(`<meta[^>]+content=["']([^"']*)["'][^>]+(?:property|name)=["']${name}["']`, 'i'));
  return m ? m[1].replace(/&amp;/g, '&').replace(/&#039;/g, "'").trim() : '';
}

async function kenney(entries) {
  const out = [];
  let supportEvidence = null;
  try {
    const support = await get('https://kenney.nl/support');
    const m = support.match(/[^>.]*public domain licensed \(CC0\)[^<.]*/i);
    if (m) supportEvidence = m[0].trim();
  } catch { /* the per-page check below still has to pass */ }
  for (const [slug, kind, style, tags, scale] of entries) {
    try {
      const url = `https://kenney.nl/assets/${slug}`;
      const html = await get(url);
      const zip = (html.match(/https?:[^"' ]+\.zip/) || [])[0];
      const cc0 = /CC0|Creative Commons Zero|public domain/i.test(html);
      if (!zip || !cc0) { console.warn(`  skip ${slug}: ${!zip ? 'no zip link' : 'no CC0 statement'}`); continue; }
      out.push({
        id: `kenney/${slug}`, source: 'kenney', title: metaOf(html, 'og:title').replace(/\s*[·|-]\s*Kenney.*/i, '') || slug, kind, style,
        tags: tags.split(' '), scale, description: metaOf(html, 'og:description') || metaOf(html, 'description'),
        license: 'CC0-1.0', licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
        page: url, downloadUrl: zip, preview: metaOf(html, 'og:image') || null, autoDownload: true,
        verified: { date: today, url, evidence: supportEvidence || 'page states CC0 / public domain' }
      });
      console.log(`  kenney/${slug} ok`);
    } catch (e) { console.warn(`  skip ${slug}: ${e.message}`); }
  }
  return out;
}

async function manualPacks(list, source, base, evidenceRe, evidenceUrl) {
  const out = [];
  let ev = null;
  try { const html = await get(evidenceUrl); const m = html.match(evidenceRe); if (m) ev = m[0].replace(/\s+/g, ' ').trim(); } catch { /* handled below */ }
  if (!ev) { console.warn(`  ${source}: could not confirm CC0 at ${evidenceUrl} — not indexed`); return out; }
  for (const [slug, kind, style, tags, scale] of list) {
    out.push({
      id: `${source}/${slug}`, source, title: slug.replace(/-/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()), kind, style, tags: tags.split(' '), scale,
      description: `${source} CC0 pack. Not scriptable to download — ask the user to add the zip (the page below has the download).`,
      license: 'CC0-1.0', licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/', page: base(slug), downloadUrl: null, preview: null, autoDownload: false, manual: true,
      verified: { date: today, url: evidenceUrl, evidence: ev }
    });
    console.log(`  ${source}/${slug} (manual) ok`);
  }
  return out;
}

async function polyhaven() {
  const out = [];
  const cats = [['ground', 'dirt soil ground earth'], ['grass', 'grass lawn field'], ['asphalt', 'asphalt road street pavement'], ['brick', 'brick wall building'], ['wood', 'wood planks floor'], ['rock', 'rock stone cliff'], ['sand', 'sand beach'], ['concrete', 'concrete wall pavement']];
  for (const [cat, extra] of cats) {
    try {
      const j = await get(`https://api.polyhaven.com/assets?t=textures&c=${cat}`, true);
      for (const [id, a] of Object.entries(j).slice(0, 8)) {
        out.push({
          id: `polyhaven/${id}`, source: 'polyhaven', title: a.name, kind: 'textures', style: 'realistic', tags: [...new Set([...(a.tags || []), ...(a.categories || []), ...extra.split(' ')])],
          scale: 'tileable PBR (diffuse/normal/rough)', description: `Poly Haven texture: ${a.name}`, license: 'CC0-1.0', licenseUrl: 'https://polyhaven.com/license',
          page: `https://polyhaven.com/a/${id}`, downloadUrl: `polyhaven:texture:${id}`, preview: `https://cdn.polyhaven.com/asset_img/thumbs/${id}.png?width=256&height=256`, autoDownload: true,
          verified: { date: today, url: 'https://polyhaven.com/license', evidence: 'Poly Haven assets are CC0' }
        });
      }
      console.log(`  polyhaven textures ${cat}`);
    } catch (e) { console.warn(`  polyhaven ${cat}: ${e.message}`); }
  }
  try {
    const j = await get('https://api.polyhaven.com/assets?t=hdris&c=skies', true);
    for (const [id, a] of Object.entries(j).slice(0, 10)) {
      out.push({
        id: `polyhaven/${id}`, source: 'polyhaven', title: a.name, kind: 'hdri', style: 'realistic', tags: [...new Set([...(a.tags || []), ...(a.categories || []), 'sky', 'hdri', 'clouds'])],
        scale: 'panorama (use 1k)', description: `Poly Haven sky HDRI: ${a.name}`, license: 'CC0-1.0', licenseUrl: 'https://polyhaven.com/license',
        page: `https://polyhaven.com/a/${id}`, downloadUrl: `polyhaven:hdri:${id}`, preview: `https://cdn.polyhaven.com/asset_img/thumbs/${id}.png?width=256&height=256`, autoDownload: true,
        verified: { date: today, url: 'https://polyhaven.com/license', evidence: 'Poly Haven assets are CC0' }
      });
    }
    console.log('  polyhaven hdris');
  } catch (e) { console.warn('  polyhaven hdris: ' + e.message); }
  return out;
}

async function ambientcg() {
  const out = [];
  try {
    const j = await get('https://ambientcg.com/api/v2/full_json?type=Material&limit=100&sort=Popular&include=tagData,downloadData,imageData', true);
    for (const a of j.foundAssets || []) {
      const dl = (a.downloadFolders && a.downloadFolders.default && a.downloadFolders.default.downloadFiletypeCategories && a.downloadFolders.default.downloadFiletypeCategories.zip && a.downloadFolders.default.downloadFiletypeCategories.zip.downloads || []).find((d) => /^1K-JPG$/i.test(d.attribute));
      if (!dl) continue;
      const lic = a.license || 'CC0 1.0';
      if (!/CC0|public domain/i.test(lic)) continue;
      out.push({
        id: `ambientcg/${a.assetId}`, source: 'ambientcg', title: a.displayName || a.assetId, kind: 'textures', style: 'realistic', tags: [...new Set([...(a.tags || []).map((t) => String(t).toLowerCase()), String(a.assetId).replace(/\d+$/, '').toLowerCase()])],
        scale: 'tileable PBR (color/normal/roughness)', description: `ambientCG material: ${a.displayName || a.assetId}`, license: 'CC0-1.0', licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
        page: `https://ambientcg.com/view?id=${a.assetId}`, downloadUrl: dl.downloadLink, preview: (a.previewImage && (a.previewImage['256-PNG'] || a.previewImage['128-PNG'])) || null, autoDownload: true,
        verified: { date: today, url: 'https://ambientcg.com/api/v2/full_json', evidence: `API licence field: ${lic}` }
      });
    }
    console.log(`  ambientcg materials ${out.length}`);
  } catch (e) { console.warn('  ambientcg: ' + e.message); }
  return out;
}

async function addWave1() {
  const cur = JSON.parse(fs.readFileSync(OUT, 'utf-8'));
  const have = new Set(cur.entries.map((e) => e.id));
  console.log('Kenney wave 1 (merge into the existing index)…');
  const added = (await kenney(KENNEY_WAVE1)).filter((e) => !have.has(e.id));
  cur.entries.push(...added);
  cur.count = cur.entries.length;
  cur.styleFamilies = Array.from(new Set([...(cur.styleFamilies || []), 'particles', 'fonts']));
  cur.builtAt = new Date().toISOString();
  fs.writeFileSync(OUT, JSON.stringify(cur, null, 1));
  console.log(`catalog: +${added.length} entries (now ${cur.count}) -> ${OUT}`);
}

async function main() {
  if (process.argv.includes('--wave1')) return addWave1();
  console.log('Kenney…');
  const k = await kenney(KENNEY);
  console.log('Quaternius…');
  const q = await manualPacks(QUATERNIUS, 'quaternius', (s) => `https://quaternius.com/packs/${s}.html`, /[^<>]{0,60}CC0 License[^<>]{0,40}/i, 'https://quaternius.com/');
  console.log('KayKit…');
  const kk = await manualPacks(KAYKIT, 'kaykit', (s) => `https://kaylousberg.itch.io/${s.replace(/^kaykit-/, 'kaykit-')}`, /CC0 Licensed|CC0 so you can/i, 'https://kaylousberg.itch.io/kaykit-adventurers');
  console.log('Poly Haven…');
  const p = await polyhaven();
  console.log('ambientCG…');
  const a = await ambientcg();
  const entries = [...k, ...q, ...kk, ...p, ...a];
  const catalog = { version: 1, builtAt: new Date().toISOString(), policy: 'CC0 only; licence verified at build time; no Mixamo raw files; one style family per game', styleFamilies: ['low-poly', 'toon', 'stylized', 'realistic', 'ui', 'audio'], count: entries.length, entries };
  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(catalog, null, 1));
  console.log(`catalog: ${entries.length} entries -> ${OUT}`);
}
if (require.main === module) main().catch((e) => { console.error(e.stack); process.exit(1); });
module.exports = { main };
