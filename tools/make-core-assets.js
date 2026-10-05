#!/usr/bin/env node
/**
 * make-core-assets — assembles kits/assets-core/, the SMALL core asset set that
 * ships inside the installer (everything bigger is downloaded on demand into the
 * shared cache). Takes a hand-picked subset of Kenney's CC0 packs from already
 * extracted folders, keeps each pack's own License.txt next to its files, and
 * writes assets-core/index.json (id, file, style family, tags, scale, licence) so
 * the catalog search can return them with zero download.
 *
 *   node kits/tools/make-core-assets.js <dir-with-extracted-kenney-packs>
 */
const fs = require('fs');
const path = require('path');

const SRC = process.argv[2];
const OUT = path.join(__dirname, '..', 'assets-core');
if (!SRC) { console.error('usage: node make-core-assets.js <extracted kenney folder>'); process.exit(1); }

const PICK = {
  'nature-kit': { dir: 'Models/GLTF format', files: /^(tree_(default|oak|pine|simple|small|thin|fat|detailed|blocks|cone|palm)[A-Za-z_]*|rock_(largeA|largeC|smallA|smallC|tallA|tallC)|plant_bush(Large|Small)?|flower_(purple|red|yellow)A|grass_large|log|stump_round|mushroom_(red|tan)|cactus_(short|tall)|fence_simple|sign)\.glb$/, tags: 'nature outdoor', style: 'low-poly' },
  'city-kit-commercial': { dir: 'Models/GLB format', files: /^(building-[a-h]|building-skyscraper-[a-c]|detail-awning|detail-parasol-a)\.glb$/, tags: 'city urban building downtown', style: 'low-poly', extra: ['Textures'] },
  'car-kit': { dir: 'Models/GLB format', files: /^(sedan|taxi|hatchback-sports|police|race|suv|van|truck|delivery)\.glb$/, tags: 'car vehicle traffic', style: 'low-poly', extra: ['Textures'] }
};

function words(name) { return name.replace(/\.glb$/, '').replace(/([a-z])([A-Z])/g, '$1 $2').split(/[_\-\s]+/).map((w) => w.toLowerCase()).filter(Boolean); }

function main() {
  fs.rmSync(OUT, { recursive: true, force: true });
  const entries = [];
  for (const [pack, cfg] of Object.entries(PICK)) {
    const from = path.join(SRC, pack, cfg.dir);
    const to = path.join(OUT, pack);
    fs.mkdirSync(to, { recursive: true });
    for (const f of fs.readdirSync(from)) {
      if (!cfg.files.test(f)) continue;
      fs.copyFileSync(path.join(from, f), path.join(to, f));
      entries.push({ id: `core/${pack}/${f.replace('.glb', '')}`, file: `${pack}/${f}`, source: 'kenney', pack, kind: 'models', style: cfg.style, tags: [...new Set([...cfg.tags.split(' '), ...words(f)])], scale: '1 unit = 1 m', license: 'CC0-1.0' });
    }
    // shared texture folder the city/car GLBs reference
    for (const extra of cfg.extra || []) {
      const ex = path.join(from, extra);
      if (fs.existsSync(ex)) { fs.mkdirSync(path.join(to, extra), { recursive: true }); for (const t of fs.readdirSync(ex)) fs.copyFileSync(path.join(ex, t), path.join(to, extra, t)); }
    }
    for (const lic of ['License.txt', 'LICENSE.txt']) { const lp = path.join(SRC, pack, lic); if (fs.existsSync(lp)) fs.copyFileSync(lp, path.join(to, 'License.txt')); }
  }
  // controller prompts: Xbox + keyboard glyphs (for controller-aware button prompts)
  const ip = path.join(SRC, 'input-prompts');
  if (fs.existsSync(ip)) {
    const to = path.join(OUT, 'input-prompts');
    for (const [folder, re] of [['Xbox Series/Default', /^xbox_(button_(a|b|x|y)|button_color_(a|b|x|y)|lb|rb|lt|rt|stick_l|stick_r|dpad|button_start|button_menu|button_view)(_outline)?\.png$/], ['Keyboard & Mouse/Default', /^keyboard_(space|enter|escape|shift|e|f|q|w|a|s|d|j|k|l|arrow_up|arrow_down|arrow_left|arrow_right)(_outline)?\.png$/]]) {
      const dir = path.join(ip, folder);
      if (!fs.existsSync(dir)) continue;
      const dest = path.join(to, folder.split('/')[0].replace(/\W+/g, '_').toLowerCase());
      fs.mkdirSync(dest, { recursive: true });
      for (const f of fs.readdirSync(dir)) {
        if (!re.test(f)) continue;
        fs.copyFileSync(path.join(dir, f), path.join(dest, f));
        entries.push({ id: `core/input-prompts/${path.basename(dest)}/${f.replace('.png', '')}`, file: `input-prompts/${path.basename(dest)}/${f}`, source: 'kenney', pack: 'input-prompts', kind: 'ui', style: 'ui', tags: ['prompt', 'button', 'glyph', 'input', path.basename(dest), ...words(f.replace('.png', '.glb'))], scale: '2D sprite', license: 'CC0-1.0' });
      }
    }
    if (fs.existsSync(path.join(ip, 'License.txt'))) fs.copyFileSync(path.join(ip, 'License.txt'), path.join(to, 'License.txt'));
  }
  fs.writeFileSync(path.join(OUT, 'index.json'), JSON.stringify({ version: 1, note: 'Bundled core set — Kenney CC0 subsets; each pack folder keeps its own License.txt.', entries }, null, 1));
  console.log(`core set: ${entries.length} assets`);
}
main();
