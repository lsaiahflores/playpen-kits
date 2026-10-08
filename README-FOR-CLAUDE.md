# PLAYPEN QUALITY KIT — read this before writing any game code

This project did NOT start blank. Playpen installed a tested Godot 4 (Compatibility
renderer) **quality kit** here: a working game with a real controller, camera, HUD,
menus, audio buses, adaptive music, juice, and a living ambient layer. **Customize it
to the design profile. Do not rewrite these systems from scratch.** Every model that
starts blank makes the same gray boxes, default sky, no sound — the kit exists so
yours doesn't.

## What you have (all under `res://playpen/`, autoloaded where noted)

| System | Use it for |
|---|---|
| `PNLook` (autoload) | The LOOK PACK (`res://playpen/lookpack.json`): palette, sky, sun, fog, tonemap, grade, glow. `PNLook.apply(env, sun)`, `PNLook.color("accent")`, `PNLook.toon(color)`, `PNLook.water_material()`, `PNLook.terrain_material()`, `PNLook.sway_material(...)`, `PNLook.glow_material(...)`, `PNLook.windows_material(...)`. **Use these materials, never a bare `StandardMaterial3D` gray.** |
| `PNSettings` (autoload) | Quality (Low/Medium/High, auto-picked for this machine), volumes, fullscreen. Scale your counts with `PNSettings.scale()`. |
| `PNViewport` | The 3D world renders at a quality-scaled resolution (UI stays sharp). Put ALL 3D under `world = viewport.world`. |
| `PNWind` (autoload) | ONE global wind value. Foliage/flags use the `wind_sway` shader and bend away from the player (`PNWind.track(player)`). |
| `PNAudio` (autoload) | Buses Master/Music/SFX/Ambience/UI, compressor, ducking. `play_track(id)`, `set_state("explore"/"danger"/"underwater"/"indoor"/"boss")`, `stinger("victory")`, `pickup(combo)` (in the music's KEY), `footstep(surface)`, `play_beds([...])`, `set_space("cave")`. |
| `Juice` (autoload) | `dust`, `sparkle`, `popup`, `squash`, `stretch`, `hit_stop`, `shake`, `blob_shadow`, `pop_in`. Use them on every impact, pickup, landing, menu. |
| `PNAmbient` | Birds/gulls/pigeons, butterflies, fireflies, motes, leaves, blowing paper, water ripples. `amb.build(player, area)` — the look pack decides what appears. |
| `PNCity`, `PNTerrain`, `PNScatter`, `PNProps`, `PNBatch` | Level DENSITY: city blocks, heightfield terrain, MultiMesh scatter (foliage/rocks/litter), palms/trees/lamps/signs/litter, mesh batching. A first-pass level must feel FULL. |
| `PNHud`, `PNMinimap`, `PNMenus`, `PNInteractable` | Counter/hearts/toasts/button prompts, a GTA-style minimap, title/pause/settings (controller-ready), interact prompts. |
| `PNFollowCamera`, `PNCritterRig`, `PNCollectibles`, `PNCheckpoint` | Camera, a procedural animated hero (recolor it / replace with a real model), pickups, checkpoints. |

Genre scripts live next to `main.gd` (`scripts/`): the controller (`PlatformerPlayer`
/ `AdventurePlayer` / `Kart`), enemies, track, race manager, AI. Their `@export`s are the
tuning knobs. `main.gd` has a `LEVEL` dictionary at the top: **change that first.**

## The 10 rules

1. **Look pack first.** Open `res://playpen/lookpack.json`; if the design profile asks for
   a different mood, edit the JSON (palette/sun/fog/ambient) — don't scatter literal colors.
2. **Never default-gray.** No `StandardMaterial3D` with the default albedo, no default sky,
   no untextured primitive. Use `PNLook.*` materials, `PNProps`, catalog assets.
3. **Dense, not empty.** Use `PNCity` / `PNTerrain` + `PNScatter` + `PNProps`. Aim for
   something interesting in every direction the camera can look.
4. **Alive.** Keep `PNAmbient` on. Add gameplay-relevant life (NPCs, enemies) on top.
5. **Juice every action:** jump/land/collect/hit/menu → the matching `Juice.*` and a `PNAudio` call.
6. **Draw calls are the budget** (8GB laptops): batch with `PNBatch`, scatter with
   `MultiMesh`, never hundreds of separate `MeshInstance3D`s, no real-time omni lights.
7. **Music is rendered, not coded.** Write music as MIDI via `playpen-music` (see
   `PLAYPEN-MUSIC.md`); never synthesize melodies with `sin()`. Original melodies only.
8. **Assets come from the catalog.** `playpen-assets search <words>` before modeling by
   hand. One style family per game (low-poly / toon / stylized / realistic). CC0 only.
9. **Controls:** Xbox + keyboard are already bound (`InputSetup`); show prompts with
   `InputSetup.prompt("jump")`. Never ask the user how they'll play.
10. **Verify visually.** Run `playpen-play` (never `godot` windowed) and look at the
    screenshots with the rubric in `PLAYPEN-QA.md`. Fix and re-check once. In your BUILT
    report, say exactly which moments you looked at.

## Per-kit quick start

* **platformer3d** — `PlatformerPlayer` (coyote 0.12s, buffer 0.14s, variable jump, corner nudge),
  `PNCity` level, litter/collectibles, checkpoints, minimap.
* **adventure3d** — `AdventurePlayer` (lock-on with `target`, 3-hit sword combo, shield `guard`,
  roll `dodge`, `jump`=interact), `Enemy` base, hearts, terrain + village + forest.
* **racing** — `Kart` (drift + mini-turbo; `race_throttle/brake/left/right/drift` actions),
  `RaceTrack` (generated loop), `RaceManager` (countdown/laps/positions), `AIDriver`, boost pads.

Unknown genre? Start from the closest kit and add the missing mechanic on top of it.

## Shooter kits (fps-arena, tps-shooter) + the brick-toy look
- A complete team deathmatch already works: studded brick arena (PNBricks), nav-mesh bots (PNBot), four weapons (PNWeapon: rifle, pistol,
  shotgun, launcher — tune the DEFS), match flow + scoreboard (PNMatch), HUD (PNShooterHud). Customize `LEVEL` in main.gd; never rewrite those systems.
- Characters are real beveled, rigged, animated models in res://models/ (made by `playpen-model figure`, see PLAYPEN-MODELING.md). Swap colors/helmets
  with `playpen-model figure --preset soldier --name hero --primary #...`. NEVER build a character from stacked boxes.
- QA: `godot -- --autoplay` starts the match; `--overview` adds a high camera. Use `playpen-play`, LOOK at the PNGs.
- Names in your plan, reports and in-game text must be ORIGINAL (heavy alien brawler, energy pistol) — never franchise names.

## RICH + LIVING BY DEFAULT (read this; it is on unless the user's words say otherwise)

Every project is **rich** unless the user asked for something simpler (pixel, 8-bit, flat colors, minimal, vector, low-poly, retro,
clean/simple...). The design bible states the choice (`richness`: rich | stylized | flat) in the user's own terms. Rich means a real
gradient sky with sun/moon glow, layered clouds and haze; textured ground with variation (instanced grass with wind sway, dirt/moss
patches, rocks, flowers); sky-tinted fog, layered horizon silhouettes, a soft vignette; a sun + fill + ambient + rim lighting rig and a
time of day; saturated graded color with subtle bloom; textured materials; rule-based scatter; wind, drifting clouds, motes.

**You do not build this by hand.** The kit mains already call `PNRich.build(world, env_node, sun, player, area, {...})` right after
`PNLook.apply(...)`. It reads the look pack (`rich`, `living`, `richness`) and `res://design-bible.json` and builds everything inside a
tier BUDGET (`PNSettings` low/medium/high: instanced grass clumps 1500/4500/11000, creature caps 24/60/140, shadow distance, particle
caps). Depth of field and light shafts run only in Play in full quality (Forward+); the Compatibility/web renderer gets fake depth
(fog + haze + horizon layers). Do not add your own flat sky, bare ground plane, or silent world.

**Living world.** A vague setting ("a world", "an island", "a kingdom", "a village") gets the FULL layer chosen from biome x time of day:
by day birds, butterflies, bees, insects, small critters, fish ripples, distant flocks, drifting clouds, falling leaves, swaying grass; at
dusk and night fireflies, bats, owls, crickets, stars with shooting stars, moonlight on water, mist; weather where it fits (rain, snow,
petals, embers). Specific genres (arena shooter, racer, puzzle) get a lighter baseline. ALWAYS at least: birds or insects by day,
fireflies or stars by night, wind everywhere. Each has a matching ambience bed (`birds_day`, `insects_day`, `crickets_night`, `owl_night`,
`night_wind`, `rain`, `rustle`, `water`, `frogs_night`, `bees`, `bat_flutter`, `pigeons`, `crows`, `hawk_cry`, plus `wind`, `waves`,
`gulls`) on the Ambience bus. Change the time of day with `rich.set_time_of_day("night")`; opts: `no_grass` / `no_ground_detail` for
built ground (cities, arenas, tracks), `height_fn` (a Callable) when the ground is terrain, `time_of_day`, `weather: ["rain"]`.
