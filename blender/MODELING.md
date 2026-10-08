# Modeling with `playpen-model` (real 3D art, headless Blender)

You are NOT limited to gray boxes and capsules. Playpen runs Blender for you; models you make arrive as .glb files with preview
sheets you can LOOK AT before placing them.

0. **Open the reference images first.** If the look sheet / `brain/references/` has pictures, open every one with your Read tool before
   you model anything, and match what you SEE (proportions, head shape, hands, armor, chunkiness, materials). Pictures outrank words:
   "LEGO / Mega Bloks" + pictures of sculpted, chunky, armored toy figures means sculpted chunky figures, NOT minifigs.
1. Look in the catalog first: `playpen-assets search <words>` (CC0, one style family). Model only what is missing.
2. **Characters and creatures: `playpen-model bases`** lists the ORGANIC body bases. Each is a smooth, sculpted body on a Rigify
   skeleton, game-sized (5-9k triangles), with idle-loop / walk-loop / run-loop / jump / attack / hit / die already animated:

   | base | silhouette | use for |
   |---|---|---|
   | `chunky-humanoid` | upright biped, big round head, wide shoulders, thick limbs, mitten hands | soldiers, heroes, townsfolk (sculpted toy figures) |
   | `hunched-digitigrade` | forward lean, reverse-jointed legs on toes, long forearms, tail | raiders, hunters, fast beasts |
   | `small-stocky` | knee-high, barrel torso, short thick limbs, big head | grunts, minions, pests |
   | `tall-lanky` | far taller than a person, narrow torso, very long thin limbs | snipers, stalkers, elders |
   | `quadruped` | four legs, horizontal spine, tail, rear hock | animals, hounds, mounts |
   | `flyer` | small body, wings wider than the body is long | birds, bats, drones |

   `playpen-model creature --base hunched-digitigrade --name brute --parts helmet:visor,jaw:mandibles,crest:spikes,claws:3 --primary #6a3f8f --secondary #43315c --accent #e8d9a8 --skin #7d9a52`
   Proportions are multipliers: `--head 1.2 --shoulders 1.1 --legs 0.9 --arms 1.0 --bulk 1.0 --scale 1.0`.
   Parts: helmet (dome|visor|horned|crest), visor, eyes, jaw (mandibles|tusks|beak), crest (spikes|fin|horns), shoulder_pads, chest_plate,
   backpack, gauntlets, boots, claws, tail_spike, wings, weapon (rifle|blade|club|shield). Customize a base; NEVER hand-stack boxes.
3. **Non-human means non-human.** An alien, creature or monster must have a NON-HUMAN silhouette: posture, leg structure, head shape,
   proportions. A recolored human with a label is a failure. Only `chunky-humanoid` is a person-shaped base; do not use it for creatures.
4. The brick-toy `playpen-model figure --preset ...` builder (rigid studded minifigs) is ONLY for when the user explicitly asked for
   minifig-style people AND none of their pictures show something else.
5. **Check your own work, once.** After each model open `review.png` (front / side / back / 3-4) and `poses.png` (walk, attack, die).
   Compare against the design, the look sheet and the reference images: right body type? reads as its role? non-human where it must be?
   matches the style of the pictures? Fix once if needed, then move on. This check is yours alone; never ask the user to approve anything.
6. **Outline match.** When the look sheet has a measured silhouette (`brain/references/silhouettes/*.png`) pass it: `--ref <that png>`.
   Playpen renders your model from 8 angles, scores the overlap with the reference outline, and logs it. Below the target? Adjust the
   proportions and re-run, at most 3 tries per character, then move on. `playpen-silhouette score --ref .. --model .. --name ..` scores any
   render by hand. Quote the scores in your BUILT report.
7. Props / buildings: write a Blender script and run `playpen-model run my_prop.py --name crate` (`import pn_blender as pb`).
   Standards: bevel every hard edge (`pb.bevel_box`, `pb.bevel_cyl`), one glossy material per color (`pb.plastic_material`), feet at the
   origin, 1 unit = 1 metre, facing +Y in Blender (= forward in Godot), 200-2500 triangles, no giant meshes.
8. In Godot: `var m = load("res://models/hero.glb").instantiate(); add_child(m); m.get_node("AnimationPlayer").play("idle-loop")`.
9. `playpen-model list` shows what exists. Blender runs only while an art job runs (it is heavy on an 8 GB machine).

Everything is original: invent Playpen's own names and designs. Capture what makes a reference recognizable (archetype, role, posture,
scale, material style, behavior); never copy a trademarked character, logo, music or text.
