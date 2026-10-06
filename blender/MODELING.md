# Modeling with `playpen-model` (real 3D art, headless Blender)

You are NOT limited to gray boxes and capsules. Playpen runs Blender for you; models you make arrive as .glb files with a
preview PNG you can LOOK AT before placing them.

1. Look in the catalog first: `playpen-assets search <words>` (CC0, one style family). Model only what is missing.
2. Characters: `playpen-model figure --preset soldier --name hero --primary #2f6fdd ...` builds a beveled, glossy, RIGGED brick-toy
   figure (studded head, helmets with visors, armor, backpack, weapons) with idle-loop / walk-loop / run-loop / jump / attack / hit / die
   animations. Presets: soldier, trooper, brawler, skirmisher, warrior. Customize colors, helmet, weapon, scale. NEVER hand-stack
   boxes to make a character.
3. Props / buildings: write a Blender script and run `playpen-model run my_prop.py --name crate` (`import pn_blender as pb`).
   Standards: bevel every hard edge (`pb.bevel_box`, `pb.bevel_cyl`), one glossy material per color (`pb.plastic_material`), feet at the
   origin, 1 unit = 1 metre, facing +Y in Blender (= forward in Godot), 200-2500 triangles, no giant meshes.
4. LOOK at the preview PNG every time. If it looks like stacked gray boxes, bevel more, add detail (studs, panels, trim), change colors.
5. In Godot: `var m = load("res://models/hero.glb").instantiate(); add_child(m); m.get_node("AnimationPlayer").play("idle-loop")`.
6. `playpen-model list` shows what exists. Blender runs only while an art job runs (it is heavy on an 8 GB machine).
