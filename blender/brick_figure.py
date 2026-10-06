"""
brick_figure — Playpen's BRICK-TOY FIGURE BUILDER (Part 7.2).

Sculpted, beveled toy figures: studded head, helmets with visors, armor plates, shoulder pads, backpacks, weapons, alien /
creature variants — glossy plastic, part-swappable, one color scheme per spec, rigged, with idle / walk / run / jump / attack /
hit / die animations. NEVER stacked gray boxes: every part is beveled, every color is its own glossy material.

    spec = {
      "preset":   "soldier" | "trooper" | "brawler" | "skirmisher" | "warrior",
      "name":     "hero",
      "colors":   {"primary": "#2f6fdd", "secondary": "#e8eef7", "accent": "#ffb627", "skin": "#f5c542", "visor": "#ff8a1f"},
      "helmet":   "visor" | "cap" | "horns" | "round" | "antenna" | "none",
      "weapon":   "rifle" | "pistol" | "energy_pistol" | "blade" | "club" | "none",
      "armor":    true, "backpack": true, "scale": 1.0
    }
    build(spec) -> {"mesh": obj, "armature": obj}

Faces +Y in Blender (= forward in Godot after glTF export), feet at z=0.
"""
import math
import bpy
from mathutils import Vector
import pn_blender as pb

PRESETS = {
    # original designs. (A "brawler" is a heavy alien bruiser; a "skirmisher" a quick shielded one; a "trooper" a small tank-backed one.)
    'soldier':    dict(scale=1.00, torso=(0.66, 0.38, 0.62), head_r=0.25, lean=0, helmet='visor', weapon='rifle', armor=True, backpack=True, arm_w=0.20, leg_w=0.28),
    'trooper':    dict(scale=0.80, torso=(0.62, 0.40, 0.50), head_r=0.31, lean=4, helmet='round', weapon='pistol', armor=False, backpack=True, arm_w=0.18, leg_w=0.26),
    'brawler':    dict(scale=1.22, torso=(0.92, 0.46, 0.66), head_r=0.24, lean=10, helmet='horns', weapon='club', armor=True, backpack=False, arm_w=0.30, leg_w=0.34),
    'skirmisher': dict(scale=0.96, torso=(0.58, 0.34, 0.56), head_r=0.23, lean=16, helmet='antenna', weapon='energy_pistol', armor=False, backpack=False, arm_w=0.17, leg_w=0.24),
    'warrior':    dict(scale=1.15, torso=(0.60, 0.34, 0.66), head_r=0.22, lean=6, helmet='cap', weapon='blade', armor=True, backpack=False, arm_w=0.18, leg_w=0.25),
}
DEFAULT_COLORS = {'primary': '#2f6fdd', 'secondary': '#e8eef7', 'accent': '#ffb627', 'skin': '#f5c542', 'visor': '#ff8a1f', 'dark': '#1d2230'}


def _mats(colors):
    c = dict(DEFAULT_COLORS); c.update(colors or {})
    return {
        'primary': pb.plastic_material('plastic_primary', c['primary']),
        'secondary': pb.plastic_material('plastic_secondary', c['secondary']),
        'accent': pb.plastic_material('plastic_accent', c['accent']),
        'skin': pb.plastic_material('plastic_skin', c['skin']),
        'visor': pb.plastic_material('plastic_visor', c['visor'], gloss=1.0, emissive=1.6),
        'dark': pb.plastic_material('plastic_dark', c['dark'], gloss=0.9),
    }


def build(spec):
    pb.reset_scene()
    p = dict(PRESETS.get(spec.get('preset', 'soldier'), PRESETS['soldier']))
    helmet = spec.get('helmet') or p['helmet']
    weapon = spec.get('weapon') or p['weapon']
    armor = p['armor'] if spec.get('armor') is None else bool(spec['armor'])
    backpack = p['backpack'] if spec.get('backpack') is None else bool(spec['backpack'])
    S = float(spec.get('scale', 1.0)) * p['scale']
    M = _mats(spec.get('colors'))
    tw, td, th = p['torso']
    lw = p['leg_w']; aw = p['arm_w']; hr = p['head_r']

    # ---- vertical layout (before scale), feet at 0
    leg_h = 0.62
    hip_h = 0.20
    torso_z0 = leg_h + hip_h - 0.02
    torso_zc = torso_z0 + th / 2
    head_zc = torso_z0 + th + hr * 0.62 + 0.02
    arm_len = 0.50
    shoulder_z = torso_z0 + th - 0.04
    arm_x = tw / 2 + aw / 2 + 0.02

    parts = {}  # bone -> [objects]

    def add(bone, ob):
        if ob is None:
            return None
        parts.setdefault(bone, []).append(ob)
        return ob

    # ---- legs + hips (hips bone) + feet
    for side, sx in (('L', 1), ('R', -1)):
        x = sx * (lw / 2 + 0.01)
        add('leg.' + side, pb.bevel_box(f'leg_{side}', (lw, td * 0.9, leg_h), (x, 0, leg_h / 2), M['dark'], bevel=0.035))
        add('leg.' + side, pb.bevel_box(f'foot_{side}', (lw + 0.02, td * 1.15, 0.08), (x, td * 0.12, 0.04), M['primary'], bevel=0.03))
    add('hips', pb.bevel_box('hips', (tw * 0.98, td * 0.95, hip_h), (0, 0, leg_h + hip_h / 2 - 0.02), M['dark'], bevel=0.035))
    add('hips', pb.bevel_box('belt', (tw * 1.01, td * 0.99, 0.06), (0, 0, leg_h + hip_h - 0.03), M['accent'], bevel=0.02))

    # ---- torso + studs on the shoulders line (the toy-brick signature)
    add('torso', pb.bevel_box('torso', (tw, td, th), (0, 0, torso_zc), M['primary'], bevel=0.04, taper=0.9))
    # chest-plate / insignia
    if armor:
        add('torso', pb.bevel_box('chest_plate', (tw * 0.78, 0.09, th * 0.62), (0, td / 2 + 0.03, torso_zc + th * 0.08), M['secondary'], bevel=0.03))
        add('torso', pb.bevel_box('chest_stripe', (tw * 0.5, 0.1, 0.07), (0, td / 2 + 0.05, torso_zc + th * 0.02), M['accent'], bevel=0.015))
    else:
        add('torso', pb.bevel_box('belly_panel', (tw * 0.55, 0.06, th * 0.45), (0, td / 2 + 0.02, torso_zc), M['secondary'], bevel=0.025))

    # ---- arms (+ hands, shoulder pads)
    for side, sx in (('L', 1), ('R', -1)):
        ax = sx * arm_x
        add('arm.' + side, pb.bevel_box(f'arm_{side}', (aw, aw * 1.15, arm_len), (ax, 0.02, shoulder_z - arm_len / 2 - 0.02), M['primary'], bevel=0.035))
        add('arm.' + side, pb.bevel_cyl(f'hand_{side}', aw * 0.62, 0.14, (ax, 0.05, shoulder_z - arm_len - 0.06), M['skin'], segments=16, bevel=0.025))
        if armor:
            pad = pb.bevel_sphere(f'pad_{side}', aw * 1.05, (ax, 0.0, shoulder_z + 0.02), M['secondary'], scale=(1.05, 1.0, 0.8), top_only=True)
            add('arm.' + side, pad)
        add('arm.' + side, pb.bevel_cyl(f'cuff_{side}', aw * 0.7, 0.06, (ax, 0.04, shoulder_z - arm_len + 0.0), M['accent'], segments=14, bevel=0.015))

    # ---- head (+ stud, face / helmet)
    add('head', pb.bevel_cyl('head', hr, hr * 1.25, (0, 0, head_zc), M['skin'], segments=22, bevel=0.03))
    add('head', pb.bevel_cyl('head_stud', hr * 0.38, 0.07, (0, 0, head_zc + hr * 0.625 + 0.035), M['skin'], segments=14, bevel=0.015))
    face_y = hr - 0.004
    _face(add, M, helmet, hr, head_zc, face_y)
    _helmet(add, M, helmet, hr, head_zc)

    # ---- backpack
    if backpack:
        add('torso', pb.bevel_box('pack', (tw * 0.62, 0.2, th * 0.62), (0, -td / 2 - 0.1, torso_zc + 0.02), M['secondary'], bevel=0.035))
        add('torso', pb.bevel_cyl('pack_tank', 0.075, th * 0.6, (tw * 0.18, -td / 2 - 0.19, torso_zc + 0.02), M['accent'], segments=14, bevel=0.015))
        add('torso', pb.bevel_cyl('pack_tank2', 0.075, th * 0.6, (-tw * 0.18, -td / 2 - 0.19, torso_zc + 0.02), M['accent'], segments=14, bevel=0.015))

    # ---- weapon / held item, in the right hand (arm.R) so it follows the arm
    hand = Vector((-arm_x, 0.05, shoulder_z - arm_len - 0.06))
    for ob in _weapon(M, weapon, hand, spec.get('preset', 'soldier')):
        add('arm.R', ob)
    if spec.get('preset') == 'skirmisher':
        add('arm.L', pb.bevel_cyl('energy_shield', 0.26, 0.05, (arm_x + 0.06, 0.2, shoulder_z - 0.3), M['visor'], segments=24, bevel=0.012, axis='X'))

    # ---- armature (bones along Z, all in unscaled units, scaled below)
    bones = [
        ('root', None, (0, 0, 0), (0, 0, 0.25)),
        ('hips', 'root', (0, 0, leg_h + 0.02), (0, 0, leg_h + hip_h)),
        ('torso', 'hips', (0, 0, torso_z0), (0, 0, torso_z0 + th)),
        ('head', 'torso', (0, 0, torso_z0 + th), (0, 0, head_zc + hr)),
        ('arm.L', 'torso', (arm_x, 0, shoulder_z), (arm_x, 0, shoulder_z - arm_len)),
        ('arm.R', 'torso', (-arm_x, 0, shoulder_z), (-arm_x, 0, shoulder_z - arm_len)),
        ('leg.L', 'hips', (lw / 2 + 0.01, 0, leg_h), (lw / 2 + 0.01, 0, 0.05)),
        ('leg.R', 'hips', (-(lw / 2 + 0.01), 0, leg_h), (-(lw / 2 + 0.01), 0, 0.05)),
    ]
    arm_ob = pb.make_armature(spec.get('name', 'figure') + '_rig', bones)
    all_objs = []
    for bone, obs in parts.items():
        for o in obs:
            pb.weight_to_bone(o, bone if bone != 'root' else 'hips')
            all_objs.append(o)
    mesh = pb.join(all_objs, spec.get('name', 'figure'))
    # lean (hunch) the torso+head for the creature presets: bake into the rest pose by tilting the torso bone chain
    pb.skin(mesh, arm_ob)
    arm_ob.scale = (S, S, S)
    mesh.scale = (1, 1, 1)
    bpy.context.view_layer.update()
    _animations(arm_ob, p['lean'])
    return {'mesh': mesh, 'armature': arm_ob, 'height': (head_zc + hr) * S}


# ------------------------------------------------------------------ face / helmets / weapons
def _face(add, M, helmet, hr, zc, fy):
    if helmet in ('visor', 'round'):
        return  # visor covers the face
    for sx in (-1, 1):
        add('head', pb.bevel_cyl('eye', hr * 0.13, 0.03, (sx * hr * 0.38, fy, zc + hr * 0.12), M['dark'], segments=12, bevel=0.006, axis='Y'))
    add('head', pb.bevel_box('mouth', (hr * 0.5, 0.025, hr * 0.1), (0, fy, zc - hr * 0.3), M['dark'], bevel=0.008))


def _helmet(add, M, helmet, hr, zc):
    if helmet == 'visor':
        add('head', pb.bevel_sphere('dome', hr * 1.12, (0, 0, zc + 0.02), M['secondary'], scale=(1.0, 1.0, 0.95), u=22, v=14, top_only=False))
        add('head', pb.bevel_box('visor', (hr * 1.55, 0.16, hr * 0.62), (0, hr * 0.78, zc + hr * 0.12), M['visor'], bevel=0.04))
        add('head', pb.bevel_cyl('dome_stud', hr * 0.34, 0.08, (0, 0, zc + hr * 1.07 + 0.03), M['secondary'], segments=16, bevel=0.016))
    elif helmet == 'round':
        add('head', pb.bevel_sphere('dome', hr * 1.18, (0, 0, zc), M['secondary'], u=22, v=14))
        add('head', pb.bevel_box('visor', (hr * 1.3, 0.14, hr * 0.7), (0, hr * 0.92, zc + 0.02), M['visor'], bevel=0.04))
    elif helmet == 'cap':
        add('head', pb.bevel_cyl('cap', hr * 1.08, hr * 0.5, (0, 0, zc + hr * 0.52), M['primary'], segments=22, bevel=0.025))
        add('head', pb.bevel_box('brim', (hr * 1.7, hr * 0.8, 0.045), (0, hr * 0.85, zc + hr * 0.3), M['primary'], bevel=0.015))
    elif helmet == 'horns':
        add('head', pb.bevel_cyl('band', hr * 1.08, hr * 0.32, (0, 0, zc + hr * 0.45), M['dark'], segments=22, bevel=0.02))
        for sx in (-1, 1):
            add('head', pb.bevel_cyl('horn', hr * 0.2, hr * 1.0, (sx * hr * 0.95, 0, zc + hr * 0.7), M['secondary'], segments=12, bevel=0.01, r2=hr * 0.03))
    elif helmet == 'antenna':
        add('head', pb.bevel_cyl('crown', hr * 1.04, hr * 0.22, (0, 0, zc + hr * 0.55), M['dark'], segments=20, bevel=0.015))
        add('head', pb.bevel_cyl('stalk', hr * 0.06, hr * 0.9, (hr * 0.5, 0, zc + hr * 1.1), M['secondary'], segments=8, bevel=0.004))
        add('head', pb.bevel_sphere('bulb', hr * 0.14, (hr * 0.5, 0, zc + hr * 1.62), M['visor'], u=12, v=8))


def _weapon(M, kind, hand, preset):
    hx, hy, hz = hand.x, hand.y, hand.z
    out = []
    if kind in (None, 'none'):
        return out
    if kind == 'rifle':
        out += [pb.bevel_box('rifle_body', (0.1, 0.62, 0.15), (hx, hy + 0.22, hz + 0.12), M['dark'], bevel=0.02),
                pb.bevel_cyl('rifle_barrel', 0.03, 0.5, (hx, hy + 0.7, hz + 0.14), M['secondary'], segments=10, bevel=0.006, axis='Y'),
                pb.bevel_box('rifle_stock', (0.09, 0.22, 0.2), (hx, hy - 0.2, hz + 0.1), M['primary'], bevel=0.02),
                pb.bevel_box('rifle_scope', (0.06, 0.2, 0.07), (hx, hy + 0.3, hz + 0.25), M['accent'], bevel=0.015),
                pb.bevel_box('rifle_mag', (0.08, 0.09, 0.2), (hx, hy + 0.18, hz - 0.02), M['accent'], bevel=0.015)]
    elif kind == 'pistol':
        out += [pb.bevel_box('pistol_slide', (0.08, 0.3, 0.1), (hx, hy + 0.22, hz + 0.1), M['dark'], bevel=0.015),
                pb.bevel_box('pistol_grip', (0.08, 0.09, 0.18), (hx, hy + 0.1, hz - 0.02), M['secondary'], bevel=0.015)]
    elif kind == 'energy_pistol':
        out += [pb.bevel_box('ep_body', (0.1, 0.34, 0.12), (hx, hy + 0.22, hz + 0.1), M['secondary'], bevel=0.02),
                pb.bevel_cyl('ep_cell', 0.05, 0.22, (hx, hy + 0.34, hz + 0.2), M['visor'], segments=12, bevel=0.01, axis='Y'),
                pb.bevel_box('ep_grip', (0.08, 0.09, 0.18), (hx, hy + 0.1, hz - 0.02), M['dark'], bevel=0.015)]
    elif kind == 'blade':
        out += [pb.bevel_box('blade_hilt', (0.07, 0.07, 0.24), (hx, hy + 0.06, hz + 0.02), M['dark'], bevel=0.015),
                pb.bevel_box('blade_guard', (0.2, 0.05, 0.05), (hx, hy + 0.06, hz + 0.16), M['accent'], bevel=0.012),
                pb.bevel_box('blade', (0.05, 0.04, 0.7), (hx, hy + 0.06, hz + 0.54), M['visor'], bevel=0.01)]
    elif kind == 'club':
        out += [pb.bevel_cyl('club_haft', 0.045, 0.7, (hx, hy + 0.05, hz + 0.22), M['dark'], segments=10, bevel=0.01),
                pb.bevel_box('club_head', (0.3, 0.3, 0.32), (hx, hy + 0.05, hz + 0.62), M['secondary'], bevel=0.04)]
    return out


# ------------------------------------------------------------------ animations (named so Godot imports loops as loops)
def _animations(arm, lean):
    L, R = 'leg.L', 'leg.R'
    AL, AR = 'arm.L', 'arm.R'
    base = {'torso': (lean * 0.5, 0, 0), 'head': (-lean * 0.35, 0, 0)}
    def P(**kw):
        d = dict(base)
        d.update(kw)
        return d
    # idle (breathing)
    pb.make_action(arm, 'idle-loop', [
        (1,  P(torso=(lean * 0.5, 0, 0), **{AL: (0, 0, -3), AR: (0, 0, 3)})),
        (30, P(torso=(lean * 0.5 + 2, 0, 0), **{AL: (3, 0, -5), AR: (3, 0, 5)})),
        (60, P(torso=(lean * 0.5, 0, 0), **{AL: (0, 0, -3), AR: (0, 0, 3)})),
    ], loop=True)
    # walk
    pb.make_action(arm, 'walk-loop', [
        (1,  P(**{L: (28, 0, 0), R: (-28, 0, 0), AL: (-22, 0, 0), AR: (22, 0, 0)})),
        (8,  P(**{L: (0, 0, 0), R: (0, 0, 0), AL: (0, 0, 0), AR: (0, 0, 0), 'hips': (0, 0, 0, (0, 0.03, 0))})),
        (15, P(**{L: (-28, 0, 0), R: (28, 0, 0), AL: (22, 0, 0), AR: (-22, 0, 0)})),
        (23, P(**{L: (0, 0, 0), R: (0, 0, 0), AL: (0, 0, 0), AR: (0, 0, 0), 'hips': (0, 0, 0, (0, 0.03, 0))})),
        (30, P(**{L: (28, 0, 0), R: (-28, 0, 0), AL: (-22, 0, 0), AR: (22, 0, 0)})),
    ], loop=True)
    # run
    pb.make_action(arm, 'run-loop', [
        (1,  P(torso=(lean * 0.5 + 12, 0, 0), **{L: (50, 0, 0), R: (-50, 0, 0), AL: (-55, 0, 0), AR: (55, 0, 0)})),
        (6,  P(torso=(lean * 0.5 + 12, 0, 0), **{L: (0, 0, 0), R: (0, 0, 0), AL: (0, 0, 0), AR: (0, 0, 0), 'hips': (0, 0, 0, (0, 0.06, 0))})),
        (11, P(torso=(lean * 0.5 + 12, 0, 0), **{L: (-50, 0, 0), R: (50, 0, 0), AL: (55, 0, 0), AR: (-55, 0, 0)})),
        (16, P(torso=(lean * 0.5 + 12, 0, 0), **{L: (0, 0, 0), R: (0, 0, 0), AL: (0, 0, 0), AR: (0, 0, 0), 'hips': (0, 0, 0, (0, 0.06, 0))})),
        (21, P(torso=(lean * 0.5 + 12, 0, 0), **{L: (50, 0, 0), R: (-50, 0, 0), AL: (-55, 0, 0), AR: (55, 0, 0)})),
    ], loop=True)
    # jump (crouch -> up -> land)
    pb.make_action(arm, 'jump', [
        (1,  P(**{L: (-30, 0, 0), R: (-30, 0, 0), 'hips': (0, 0, 0, (0, -0.1, 0)), AL: (20, 0, 0), AR: (20, 0, 0)})),
        (8,  P(**{L: (10, 0, 0), R: (10, 0, 0), 'hips': (0, 0, 0, (0, 0.18, 0)), AL: (-150, 0, 0), AR: (-150, 0, 0)})),
        (20, P(**{L: (-15, 0, 0), R: (15, 0, 0), 'hips': (0, 0, 0, (0, 0.1, 0)), AL: (-120, 0, 0), AR: (-120, 0, 0)})),
        (30, P(**{L: (-25, 0, 0), R: (-25, 0, 0), 'hips': (0, 0, 0, (0, -0.06, 0)), AL: (10, 0, 0), AR: (10, 0, 0)})),
    ])
    # attack / shoot (right arm raises, recoil)
    pb.make_action(arm, 'attack', [
        (1,  P(**{AR: (-85, 0, 0), AL: (-40, 0, 12)})),
        (4,  P(torso=(lean * 0.5 - 5, 0, 0), **{AR: (-95, 0, 0), AL: (-40, 0, 12)})),
        (15, P(**{AR: (-85, 0, 0), AL: (-40, 0, 12)})),
    ])
    # hit reaction
    pb.make_action(arm, 'hit', [
        (1,  P()),
        (4,  P(torso=(lean * 0.5 - 16, 0, 0), head=(-lean * 0.35 - 20, 0, 0), **{AL: (-30, 0, 0), AR: (-30, 0, 0)})),
        (12, P()),
    ])
    # die (fall backward)
    pb.make_action(arm, 'die', [
        (1,  P(root=(0, 0, 0, (0, 0, 0)))),
        (14, P(root=(-40, 0, 0, (0, 0, 0)), **{AL: (-60, 0, 0), AR: (-60, 0, 0)})),
        (30, P(root=(-88, 0, 0, (0, 0, 0)), **{AL: (-90, 0, 12), AR: (-90, 0, -12)})),
        (36, P(root=(-88, 0, 0, (0, 0, 0)), **{AL: (-90, 0, 12), AR: (-90, 0, -12)})),
    ])
    # rest pose the exporter sees
    for pbn in arm.pose.bones:
        pbn.rotation_mode = 'XYZ'
        pbn.rotation_euler = (0, 0, 0)
        pbn.location = (0, 0, 0)
    # active action: idle so viewers see something alive
    arm.animation_data.action = bpy.data.actions['idle-loop']
