# VISUAL QA — check your own work before you report

Every AI-made game fails the same way: a default gray sky, flat untextured boxes, nothing
alive, nothing to look at. You have the eyes to catch it — use them. **After building, and
only through Playpen** (never a windowed `godot`), do this loop:

1. `playpen-play --wait 8000 --input "key:Enter,wait:1200,shot,key:Up,wait:1500,shot,key:Esc,wait:600,shot"`
   — boots the game in the Test area and saves screenshots of key moments (title, gameplay,
   moving, pause). Take at least **title, first gameplay view, a second view after moving, pause**.
2. `playpen-qa` — checks the saved PNGs automatically and prints PASS / WARN / FAIL lines plus
   a colour-similarity score against the user's inspiration references.
3. **LOOK at every PNG** and go through the rubric below. Be harsh. If you would not show it
   to a friend, it is a fail.
4. Fix every failure (look pack, lighting, density, materials, camera, HUD), run steps 1–3
   again **once**, then report. Do not loop forever; say plainly what is still weak.

## The rubric

| Check | Pass looks like | Fail looks like |
|---|---|---|
| **No default gray sky** | A gradient sky with clouds / sun glow / haze in the look pack's colours | Flat gray or engine-default blue-gray |
| **No untextured primitives** | Everything has a styled material (toon / sway / water / windows / terrain) | Default white/gray boxes, spheres, capsules |
| **Look-pack palette applied** | The frame is clearly the pack's colours (sunny = warm & saturated, night = blue & glowing…) | A random mix; muddy; gray |
| **Real lighting contrast** | Sun and shadow, bright lit sides vs shaded sides, a sense of depth and haze | Flat, evenly lit, no shadows |
| **Ambient life visible** | Birds / gulls / pigeons / butterflies / clouds / swaying foliage / drifting motes in at least one shot | Static, frozen world |
| **Dense, not four boxes** | Something interesting in every direction the camera can see: buildings, props, foliage, signs, ground detail | A big empty plane with a few objects |
| **HUD readable** | Text/icons legible, correct genre placement, not covering the action, button prompts match the controller | Overlapping, clipped, tiny or missing |
| **Matches the references** | Mood, palette, level of detail resemble what the user attached | Ignores the references |
| **Menus work** | Title shows, Play starts, pause opens, settings has volume/quality/fullscreen | Dead buttons, missing pause |

## What to write in BUILT

List the moments you actually looked at ("title, first street view, after running, pause menu"),
what `playpen-qa` flagged and what you changed, and what is still weaker than you'd like.
If you could not run `playpen-play` or the shots were blank, say that plainly — never claim you
checked something you did not see.

## Common fixes

* Gray / flat → `PNLook.apply(env, sun)` is missing or the look pack file is empty; use `PNLook.toon/…` materials.
* Empty level → raise `PNCity` blocks / `PNScatter` counts / `PNProps.trees`, add `PNProps.litter`/signs/lamps.
* No life → `PNAmbient.build(player, area)` is not called; check `ambient` in `lookpack.json`.
* Washed out → fog density too high, or sun/ambient too bright in the pack.
* Slow → too many separate meshes: batch with `PNBatch`, scatter with MultiMesh.
