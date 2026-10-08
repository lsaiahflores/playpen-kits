"""
parts — the hard-surface PART LIBRARY (Part 7.3): helmets, visors, armor plates, jaws, crests, horns, claws, wings, weapons.
Bevelled, glossy, attached to the organic body's bones. Claude picks and customizes parts; it does not model armor from cubes.

Every part function: part(spec, cols, **kw) -> [ {obj, bone, skinned} ]  (bone = a key of the base's `attach` table).
Coordinates: the base's joints are in Rigify's convention; pn_organic.game() turns them to face +Y (the front of a character is +Y).
"""
import math
import bpy, bmesh
from mathutils import Vector, Matrix
import pn_blender as pb
from pn_organic import game


def J(spec, name):
    return game(spec['joints'][name])


def _mat(cols, key, name, **kw):
    return pb.plastic_material(name, cols.get(key, '#888888'), **kw)


def cone(name, radius, length, base, direction, material, tip=0.0, segments=14):
    """A cone/spike whose BASE centre is at `base` and whose tip points along `direction`."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=tip, depth=length)
    for v in bm.verts:
        v.co.z += length / 2
    rot = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(bm, matrix=rot, verts=bm.verts)
    for f in bm.faces:
        f.smooth = abs(f.normal.dot(Vector(direction).normalized())) < 0.85
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = Vector(base)
    ob.data.materials.append(material)
    return ob


def _hr(spec):
    """Head radii (half width, half depth) and centre, in game coordinates."""
    nd = spec['nodes']['head_c']
    return game(nd[0]), nd[1], nd[2]


# ---------------------------------------------------------------- head
def helmet(spec, cols, kind='dome'):
    c, rx, ry = _hr(spec)
    if kind == 'none':
        return []
    out = []
    m = _mat(cols, 'primary', 'armor')
    if kind in ('dome', 'visor', 'horned', 'crest'):
        # a full round shell around the whole head (a chunky toy helmet), not a cap perched on top
        o = pb.bevel_sphere('helmet', 1.0, loc=(c.x, c.y - ry * 0.04, c.z + rx * 0.02), material=m, scale=(rx * 1.2, ry * 1.2, rx * 1.2), u=26, v=16)
        out.append({'obj': o, 'bone': 'head'})
        rim = pb.bevel_cyl('helmet_rim', rx * 1.08, rx * 0.12, loc=(c.x, c.y - ry * 0.04, c.z - rx * 0.72), material=_mat(cols, 'secondary', 'trim'), segments=24, bevel=0.012)
        rim.scale = (1.0, ry / rx * 1.02, 1.0)
        out.append({'obj': rim, 'bone': 'head'})
    if kind == 'horned':
        for s in (-1, 1):
            h = cone('horn', rx * 0.3, rx * 1.1, (c.x + s * rx * 0.75, c.y, c.z + rx * 0.7), (s * 0.55, 0.0, 1.0), _mat(cols, 'accent', 'horn'), tip=rx * 0.04)
            out.append({'obj': h, 'bone': 'head'})
    if kind == 'crest':
        out += crest(spec, cols, kind='fin')
    return out


def visor(spec, cols, glow=1.2):
    c, rx, ry = _hr(spec)
    o = pb.bevel_sphere('visor', 1.0, loc=(c.x, c.y + ry * 0.74, c.z + rx * 0.08), material=pb.plastic_material('visor', cols.get('visor', '#ff8a1f'), gloss=1.0, emissive=glow, rough=0.05),
                        scale=(rx * 0.82, ry * 0.5, rx * 0.4), u=22, v=12)
    return [{'obj': o, 'bone': 'head'}]


def eyes(spec, cols, spread=0.42, size=0.17, glow=2.0):
    c, rx, ry = _hr(spec)
    out = []
    for s in (-1, 1):
        o = pb.bevel_sphere('eye', rx * size, loc=(c.x + s * rx * spread, c.y + ry * 0.82, c.z + rx * 0.14),
                            material=pb.plastic_material('eye', cols.get('visor', '#ffb627'), gloss=1.0, emissive=glow, rough=0.05), scale=(1.0, 0.55, 1.1), u=14, v=10)
        out.append({'obj': o, 'bone': 'head'})
    return out


def jaw(spec, cols, kind='mandibles'):
    c, rx, ry = _hr(spec)
    m = _mat(cols, 'accent', 'bone')
    out = []
    if kind == 'mandibles':
        for s in (-1, 1):
            out.append({'obj': cone('mandible', rx * 0.18, rx * 0.9, (c.x + s * rx * 0.28, c.y + ry * 0.85, c.z - rx * 0.38), (s * -0.35, 1.0, -0.35), m, tip=rx * 0.02), 'bone': 'head'})
    elif kind == 'tusks':
        for s in (-1, 1):
            out.append({'obj': cone('tusk', rx * 0.2, rx * 1.0, (c.x + s * rx * 0.4, c.y + ry * 0.7, c.z - rx * 0.45), (s * 0.15, 0.45, 1.0), m, tip=rx * 0.02), 'bone': 'head'})
    elif kind == 'beak':
        out.append({'obj': cone('beak', rx * 0.45, rx * 1.2, (c.x, c.y + ry * 0.7, c.z - rx * 0.1), (0, 1.0, -0.15), m, tip=rx * 0.03), 'bone': 'head'})
    return out


def crest(spec, cols, kind='spikes', count=5):
    c, rx, ry = _hr(spec)
    m = _mat(cols, 'accent', 'crest')
    out = []
    if kind == 'spikes':
        for i in range(count):
            t = i / max(1, count - 1)
            y = c.y + ry * (0.5 - 1.5 * t)
            z = c.z + rx * (0.85 - 0.25 * t)
            out.append({'obj': cone('spike', rx * 0.2, rx * (0.8 - 0.3 * t), (c.x, y, z), (0, -0.5 * t, 1.0), m, tip=rx * 0.02), 'bone': 'head'})
    elif kind == 'fin':
        o = pb.bevel_box('fin', (rx * 0.08, ry * 2.0, rx * 0.9), loc=(c.x, c.y - ry * 0.4, c.z + rx * 0.95), material=m, bevel=rx * 0.03, taper=0.5)
        out.append({'obj': o, 'bone': 'head'})
    elif kind == 'horns':
        for s in (-1, 1):
            out.append({'obj': cone('horn', rx * 0.25, rx * 1.3, (c.x + s * rx * 0.55, c.y + ry * 0.1, c.z + rx * 0.75), (s * 0.5, -0.15, 1.0), m, tip=rx * 0.03), 'bone': 'head'})
    return out


# ---------------------------------------------------------------- torso + limbs
def shoulder_pads(spec, cols, size=1.0):
    out = []
    nd = spec['nodes']
    for s in ('L', 'R'):
        p = game(nd['shoulder.' + s][0]); r = nd['shoulder.' + s][1] * 1.55 * size
        o = pb.bevel_sphere('pauldron', r, loc=(p.x, p.y, p.z + r * 0.18), material=_mat(cols, 'primary', 'armor'), scale=(1.0, 0.9, 0.78), u=18, v=10, top_only=True)
        out.append({'obj': o, 'bone': 'shoulder.' + s})
    return out


def chest_plate(spec, cols):
    nd = spec['nodes']
    p = game(nd['spine3'][0]); rx, ry = nd['spine3'][1], nd['spine3'][2]
    body = pb.bevel_box('chest_plate', (rx * 1.75, ry * 1.1, rx * 1.4), loc=(p.x, p.y + ry * 0.62, p.z - rx * 0.12), material=_mat(cols, 'primary', 'armor'), bevel=rx * 0.14, taper=0.82)
    belt = pb.bevel_box('belt', (rx * 1.95, ry * 2.1, rx * 0.22), loc=(p.x, p.y, game(nd['spine1'][0]).z), material=_mat(cols, 'dark', 'belt'), bevel=0.012)
    return [{'obj': body, 'bone': 'chest'}, {'obj': belt, 'bone': 'belly'}]


def backpack(spec, cols):
    nd = spec['nodes']
    p = game(nd['spine3'][0]); rx, ry = nd['spine3'][1], nd['spine3'][2]
    o = pb.bevel_box('backpack', (rx * 1.3, ry * 1.2, rx * 1.35), loc=(p.x, p.y - ry * 1.4, p.z - rx * 0.1), material=_mat(cols, 'secondary', 'pack'), bevel=rx * 0.1, taper=0.85)
    return [{'obj': o, 'bone': 'back'}]


def gauntlets(spec, cols):
    out = []
    nd = spec['nodes']
    for s in ('L', 'R'):
        a, b = game(nd['elbow.' + s][0]), game(nd['wrist.' + s][0])
        mid = (a + b) / 2
        r = nd['elbow.' + s][1] * 1.45
        o = pb.bevel_cyl('gauntlet', r, (b - a).length * 0.62, loc=(mid.x, mid.y, mid.z), material=_mat(cols, 'secondary', 'trim'), segments=16, bevel=0.012)
        # lay it along the forearm
        d = (b - a).normalized()
        o.rotation_euler = Vector((0, 0, 1)).rotation_difference(d).to_euler()
        out.append({'obj': o, 'bone': 'forearm.' + s})
    return out


def boots(spec, cols):
    out = []
    nd = spec['nodes']
    for s in ('L', 'R'):
        a, b = game(nd['ankle.' + s][0]), game(nd['toe_base.' + s][0])
        mid = (a + b) / 2
        r = nd['ankle.' + s][1] * 1.4
        o = pb.bevel_box('boot', (r * 1.7, (b - a).length + r * 1.4, r * 1.3), loc=(mid.x, mid.y + r * 0.35, max(mid.z, r * 0.65)), material=_mat(cols, 'dark', 'boots'), bevel=r * 0.35)
        out.append({'obj': o, 'bone': 'foot.' + s})
    return out


def claws(spec, cols, where='hands', count=3):
    out = []
    nd = spec['nodes']
    m = _mat(cols, 'accent', 'claw')
    for s in ('L', 'R'):
        end = game(nd['hand_end.' + s][0]) if 'hand_end.' + s in nd else game(nd['fpaw.' + s][0])
        r = 0.018 * spec['scale'] * 2.4
        for i in range(count):
            off = (i - (count - 1) / 2) * r * 2.2
            out.append({'obj': cone('claw', r * 0.9, r * 4.0, (end.x + off, end.y, end.z), (0.0, 0.7, -0.5), m, tip=0.002), 'bone': 'hand.' + s})
    return out


def tail_spike(spec, cols):
    j = spec['joints']
    key = 'tail3' if 'tail3' in j else None
    if not key:
        return []
    p = game(j[key])
    nodes = spec['nodes']
    r = nodes.get(key, ((0, 0, 0), 0.03))[1] * 1.6
    return [{'obj': cone('tail_spike', r, r * 5, (p.x, p.y, p.z), (0, -1.0, -0.15), _mat(cols, 'accent', 'spike'), tip=0.003), 'bone': 'tail_tip'}]


def wings(spec, cols, style='membrane'):
    """Wing membranes spanning the arm bones (the flyer's arms ARE the wings). Skinned across the arm bones so they flap with them."""
    out = []
    j = spec['joints']
    m = _mat(cols, 'secondary', 'wing', gloss=0.4)
    for s in ('L', 'R'):
        sh, el, wr, he = (game(j[k + '.' + s]) for k in ('shoulder', 'elbow', 'wrist', 'hand_end'))
        bm = bmesh.new()
        drop = spec['scale'] * 0.28
        pts = [sh, el, wr, he, he + Vector((-0.02 * (1 if s == 'L' else -1), -0.20 * spec['scale'] * 2, -drop * 0.5)),
               wr + Vector((0, -0.34 * spec['scale'] * 1.7, -drop)), el + Vector((0, -0.30 * spec['scale'] * 1.7, -drop * 0.6)), sh + Vector((0, -0.08, -0.05))]
        vs = [bm.verts.new(p) for p in pts]
        try:
            bm.faces.new(vs)
        except ValueError:
            pass
        bmesh.ops.triangulate(bm, faces=list(bm.faces))
        # thicken: solidify via a tiny extrusion so it survives export lighting from both sides
        geom = list(bm.faces)
        ret = bmesh.ops.extrude_face_region(bm, geom=geom)
        verts = [e for e in ret['geom'] if isinstance(e, bmesh.types.BMVert)]
        bmesh.ops.translate(bm, vec=(0, 0, 0.006), verts=verts)
        me = bpy.data.meshes.new('wing')
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new('wing.' + s, me)
        bpy.context.scene.collection.objects.link(ob)
        ob.data.materials.append(m)
        out.append({'obj': ob, 'bone': None, 'skinned': True})
    return out


def weapon(spec, cols, kind='rifle'):
    nd = spec['nodes']
    h = game(nd['hand_end.R'][0] if 'hand_end.R' in nd else nd['fpaw.R'][0])
    s = spec['scale']
    dark = _mat(cols, 'dark', 'gunmetal', metallic=0.4)
    out = []
    if kind == 'rifle':
        body = pb.bevel_box('rifle', (0.07 * s, 0.62 * s, 0.1 * s), loc=(h.x, h.y + 0.12 * s, h.z + 0.02 * s), material=dark, bevel=0.012)
        mag = pb.bevel_box('rifle_mag', (0.05 * s, 0.09 * s, 0.14 * s), loc=(h.x, h.y + 0.08 * s, h.z - 0.1 * s), material=_mat(cols, 'accent', 'mag'), bevel=0.01)
        out += [{'obj': body, 'bone': 'hand.R'}, {'obj': mag, 'bone': 'hand.R'}]
    elif kind == 'blade':
        blade = pb.bevel_box('blade', (0.03 * s, 0.05 * s, 0.7 * s), loc=(h.x, h.y, h.z + 0.38 * s), material=pb.plastic_material('energy', cols.get('visor', '#7fd6ff'), gloss=1.0, emissive=2.5, rough=0.05), bevel=0.006)
        out.append({'obj': blade, 'bone': 'hand.R'})
    elif kind == 'club':
        club = pb.bevel_cyl('club', 0.06 * s, 0.7 * s, loc=(h.x, h.y, h.z + 0.25 * s), material=_mat(cols, 'accent', 'wood'), r2=0.1 * s, segments=14, bevel=0.01)
        out.append({'obj': club, 'bone': 'hand.R'})
    elif kind == 'shield':
        sh = game(nd['wrist.L'][0] if 'wrist.L' in nd else nd['fpaw.L'][0])
        plate = pb.bevel_box('shield', (0.05 * s, 0.4 * s, 0.5 * s), loc=(sh.x + 0.08 * s, sh.y, sh.z), material=_mat(cols, 'secondary', 'shield'), bevel=0.02, taper=0.9)
        out.append({'obj': plate, 'bone': 'hand.L'})
    return out


PARTS = {
    'helmet': helmet, 'visor': visor, 'eyes': eyes, 'jaw': jaw, 'crest': crest, 'shoulder_pads': shoulder_pads, 'chest_plate': chest_plate,
    'backpack': backpack, 'gauntlets': gauntlets, 'boots': boots, 'claws': claws, 'tail_spike': tail_spike, 'wings': wings, 'weapon': weapon,
}


def catalog():
    return [{'part': k, 'doc': (v.__doc__ or '').strip().split('\n')[0]} for k, v in PARTS.items()]
