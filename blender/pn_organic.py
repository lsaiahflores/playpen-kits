"""
pn_organic — Playpen's ORGANIC character pipeline (Part 7.2-7.4). Runs inside `blender --background` via `playpen-model creature`.

  1. A scripted SKELETON GRAPH (joints + radii) -> Skin modifier -> smooth organic body. Metaballs add bulk (brow, snout, belly).
  2. The body, blobs and added bulk are fused with a VOXEL REMESH, smoothed, and decimated to a game-ready triangle budget.
  3. Hard-surface parts (armor, helmets, visors, jaws, crests) are beveled and attached on top (parts.py).
  4. The SAME joint table fits a Rigify metarig (basic_human / basic_quadruped); Rigify generates the control rig; weights come
     from distance to the deform bones; base animations are keyed on the FK controls; export keeps only deform bones.

Conventions: joint tables are written in Rigify's own convention (character faces -Y, its LEFT is +X, feet at z=0). Everything is turned
180 degrees about Z once, so the model ends up facing +Y like every other Playpen model (+Y in Blender = forward in Godot).
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector, Matrix, Quaternion

here = os.path.dirname(os.path.abspath(__file__))
if here not in sys.path:
    sys.path.insert(0, here)
import pn_blender as pb


# Blender's Skin radius comes out about half of what a width/2 table implies; the tables are written as real half-widths.
SKIN_GAIN = 1.4


def game(p):
    """Rigify convention (faces -Y, left +X) -> Playpen convention (faces +Y): a 180 degree turn about Z."""
    return Vector((-p[0], -p[1], p[2]))


from bases import mirror_joints, mirror_skin  # noqa: E402,F401  (pure Python, so the tables can be tested without Blender)


# ------------------------------------------------------------------ 1. the organic body
def skin_body(name, nodes, edges, subdiv=3):
    """nodes: {name: ((x,y,z), rx, ry, group)}, edges: [(a, b)]. Returns a smooth mesh object (modifiers applied)."""
    bm = bmesh.new()
    layer = bm.verts.layers.skin.verify()
    vmap = {}
    for n, v in nodes.items():
        vert = bm.verts.new(game(v[0]))
        vert[layer].radius = (v[1] * SKIN_GAIN, v[2] * SKIN_GAIN)
        vmap[n] = vert
    for a, b in edges:
        bm.edges.new((vmap[a], vmap[b]))
    root = next(iter(nodes))
    vmap[root][layer].use_root = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    m = ob.modifiers.new('Skin', 'SKIN')
    m.use_smooth_shade = True
    m.branch_smoothing = 0.8
    s = ob.modifiers.new('Sub', 'SUBSURF')
    s.levels = subdiv; s.render_levels = subdiv
    apply_modifiers(ob)
    return ob


def apply_modifiers(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    if old.users == 0:
        bpy.data.meshes.remove(old)
    return ob


def metaball_blob(name, blobs, resolution=0.04):
    """blobs: [((x,y,z), radius, (sx,sy,sz))] in Rigify convention. Returns a mesh object (the metaball union, converted)."""
    mb = bpy.data.metaballs.new(name)
    mb.resolution = resolution; mb.render_resolution = resolution; mb.threshold = 0.6
    ob = bpy.data.objects.new(name, mb)
    bpy.context.scene.collection.objects.link(ob)
    for pos, r, sc in blobs:
        e = mb.elements.new(type='BALL')
        e.co = game(pos); e.radius = r; e.size_x = sc[0]; e.size_y = sc[1]; e.size_z = sc[2]
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    mesh_ob = bpy.data.objects.new(name + '_mesh', me)
    bpy.context.scene.collection.objects.link(mesh_ob)
    bpy.data.objects.remove(ob)
    bpy.data.metaballs.remove(mb)
    return mesh_ob


def fuse_and_smooth(objs, name, voxel=0.028, smooth_iter=3, target_tris=4200, paint=None):
    """Join the organic pieces, VOXEL REMESH them into one watertight surface, smooth, decimate to the triangle budget."""
    objs = [o for o in objs if o is not None]
    ob = pb.join(objs, name) if len(objs) > 1 else objs[0]
    ob.name = name
    bpy.context.view_layer.objects.active = ob
    r = ob.modifiers.new('Remesh', 'REMESH')
    r.mode = 'VOXEL'; r.voxel_size = voxel; r.use_smooth_shade = True
    apply_modifiers(ob)
    sm = ob.modifiers.new('Smooth', 'SMOOTH')
    sm.factor = 0.6; sm.iterations = smooth_iter
    apply_modifiers(ob)
    if paint:
        paint(ob)          # painted while the surface is still dense, so colour borders are smooth curves
    ob.data.calc_loop_triangles()
    tris = len(ob.data.loop_triangles)
    if tris > target_tris:
        d = ob.modifiers.new('Decimate', 'DECIMATE')
        d.ratio = max(0.02, target_tris / float(tris))
        apply_modifiers(ob)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


# ------------------------------------------------------------------ colour regions
def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / (ab.dot(ab) or 1e-9)))
    return (p - (a + ab * t)).length


def paint_regions(ob, nodes, edges, region_materials, default):
    """Give every face the material of the nearest skeleton segment's GROUP (e.g. 'torso' -> armor, 'legs' -> dark)."""
    mats = {}
    def slot(m):
        if m.name not in mats:
            ob.data.materials.append(m)
            mats[m.name] = len(ob.data.materials) - 1
        return mats[m.name]
    segs = []
    for a, b in edges:
        pa, pb_ = game(nodes[a][0]), game(nodes[b][0])
        segs.append((pa, pb_, nodes[b][3] if len(nodes[b]) > 3 else 'body'))
    default_slot = slot(default)
    group_of = {}
    for poly in ob.data.polygons:
        c = poly.center
        best, grp = 1e9, None
        for pa, pb_, g in segs:
            d = seg_dist(c, pa, pb_)
            if d < best:
                best, grp = d, g
        group_of[poly.index] = grp
    # clean the boundaries: each face takes the majority group of its neighbours (2 passes), so colour regions are smooth curves, not torn edges
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    for _ in range(3):
        nxt = dict(group_of)
        for f in bm.faces:
            votes = {}
            for e in f.edges:
                for nf in e.link_faces:
                    if nf is not f:
                        votes[group_of[nf.index]] = votes.get(group_of[nf.index], 0) + 1
            votes[group_of[f.index]] = votes.get(group_of[f.index], 0) + 1
            nxt[f.index] = max(votes.items(), key=lambda kv: kv[1])[0]
        group_of = nxt
    bm.free()
    for poly in ob.data.polygons:
        m = region_materials.get(group_of[poly.index])
        poly.material_index = slot(m) if m is not None else default_slot


# ------------------------------------------------------------------ metarig + rigify
def enable_rigify():
    import addon_utils
    addon_utils.enable('rigify', default_set=True, persistent=False)


def fit_metarig(kind, joints, bone_map, delete=()):
    """Create the Rigify basic metarig, then place every bone from the base's joint table (head joint -> tail joint)."""
    bpy.ops.object.select_all(action='DESELECT')
    getattr(bpy.ops.object, {'human': 'armature_basic_human_metarig_add', 'quadruped': 'armature_basic_quadruped_metarig_add'}[kind])()
    meta = bpy.context.active_object
    bpy.ops.object.mode_set(mode='EDIT')
    eb = meta.data.edit_bones
    for n in delete:
        if n in eb:
            eb.remove(eb[n])
    # a bone's roll keeps its numeric value; moving head/tail first can flip it, so disconnect, place, reconnect
    connected = [b.name for b in eb if b.use_connect]
    for b in eb:
        b.use_connect = False
    for bone, (ja, jb) in bone_map.items():
        if bone not in eb:
            continue
        b = eb[bone]
        b.head = game(joints[ja]); b.tail = game(joints[jb])
    # Rigify finds a limb's chain through the connected flags, so give them back (every connected pair shares one joint in the tables)
    for n in connected:
        if n in eb:
            eb[n].use_connect = True
    # keep every bone's axis roll lateral: reset roll to 0 for limb bones so FK controls rotate predictably
    for b in eb:
        if any(k in b.name for k in ('thigh', 'shin', 'foot', 'toe', 'spine', 'head', 'neck')):
            b.roll = 0.0
    bpy.ops.object.mode_set(mode='OBJECT')
    return meta


def generate_rig(meta):
    bpy.context.view_layer.objects.active = meta
    meta.select_set(True)
    bpy.ops.pose.rigify_generate()
    rig = bpy.context.active_object
    # Rigify keeps the metarig and its widget shapes in the scene; neither belongs in the exported character.
    for o in list(bpy.data.objects):
        if o.name.startswith('WGT') or o is meta:
            bpy.data.objects.remove(o)
    return rig


def deform_bones(rig):
    out = []
    for b in rig.data.bones:
        if b.use_deform:
            out.append((b.name, rig.matrix_world @ b.head_local, rig.matrix_world @ b.tail_local))
    return out


def weight_to_bones(ob, rig, max_influence=3, falloff=1.7):
    """Distance-based skin weights to the DEFORM bones (deterministic, no bone-heat failures on skin meshes)."""
    bones = deform_bones(rig)
    for name, _, _ in bones:
        if name not in ob.vertex_groups:
            ob.vertex_groups.new(name=name)
    me = ob.data
    for v in me.vertices:
        p = ob.matrix_world @ v.co
        ds = sorted(((seg_dist(p, h, t), n) for n, h, t in bones), key=lambda x: x[0])[:max_influence]
        ws = [1.0 / ((d + 0.015) ** falloff) for d, _ in ds]
        tot = sum(ws)
        for (d, n), w in zip(ds, ws):
            ob.vertex_groups[n].add([v.index], w / tot, 'REPLACE')
    return ob


def bind(ob, rig):
    mod = ob.modifiers.new('Armature', 'ARMATURE')
    mod.object = rig
    ob.parent = rig


def weight_part(part, rig, bone):
    """A rigid part (armor, helmet, jaw...) is weighted 100% to one deform bone."""
    vg = part.vertex_groups.new(name=bone)
    vg.add(list(range(len(part.data.vertices))), 1.0, 'REPLACE')


# ------------------------------------------------------------------ animation (FK controls)
def _rest_rot(rig, pbone):
    return pbone.bone.matrix_local.to_3x3()


def key_rot(rig, bone, world_axis, degrees, frame):
    """Rotate a pose bone by `degrees` about a WORLD axis (as seen in rest), keyed at `frame`."""
    pbn = rig.pose.bones.get(bone)
    if pbn is None:
        return
    R = _rest_rot(rig, pbn)
    Rw = Matrix.Rotation(math.radians(degrees), 3, Vector(world_axis))
    q = (R.inverted() @ Rw @ R).to_quaternion()
    pbn.rotation_mode = 'QUATERNION'
    pbn.rotation_quaternion = q
    pbn.keyframe_insert('rotation_quaternion', frame=frame)


AXES = {'x': (1, 0, 0), 'y': (0, 1, 0), 'z': (0, 0, 1)}


def key_pose(rig, frame, pose):
    """pose: {bone: {'rot': [('x', deg), ('z', deg)...], 'loc': (x, y, z)}} — rotations about WORLD axes (as the rest pose sees them)."""
    for bone, spec in pose.items():
        pbn = rig.pose.bones.get(bone)
        if pbn is None:
            continue
        R = _rest_rot(rig, pbn)
        Rw = Matrix.Identity(3)
        for axis, deg in spec.get('rot', []):
            Rw = Matrix.Rotation(math.radians(deg), 3, Vector(AXES[axis])) @ Rw
        pbn.rotation_mode = 'QUATERNION'
        pbn.rotation_quaternion = (R.inverted() @ Rw @ R).to_quaternion()
        pbn.keyframe_insert('rotation_quaternion', frame=frame)
        if 'loc' in spec:
            pbn.location = R.inverted() @ Vector(spec['loc'])
            pbn.keyframe_insert('location', frame=frame)


def key_loc(rig, bone, world_offset, frame):
    pbn = rig.pose.bones.get(bone)
    if pbn is None:
        return
    R = _rest_rot(rig, pbn)
    pbn.location = R.inverted() @ Vector(world_offset)
    pbn.keyframe_insert('location', frame=frame)


def reset_pose(rig):
    for pbn in rig.pose.bones:
        pbn.rotation_mode = 'QUATERNION'
        pbn.rotation_quaternion = (1, 0, 0, 0)
        pbn.location = (0, 0, 0)


def set_fk(rig):
    for n in rig.pose.bones.keys():
        if n.endswith('_parent.L') or n.endswith('_parent.R'):
            pbn = rig.pose.bones[n]
            if 'IK_FK' in pbn.keys():
                pbn['IK_FK'] = 1.0


def new_action(rig, name, loop):
    ad = rig.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ad.action = act
    reset_pose(rig)
    return act


def finish_action(rig, act, loop, fps=30):
    if loop:
        for fc in act.fcurves:
            fc.modifiers.new('CYCLES')
    bpy.context.scene.render.fps = fps
    rig.animation_data.action = None
    reset_pose(rig)


# ------------------------------------------------------------------ export + review renders
def export_character(path, rig, mesh_obs, animations=True):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True)
    for o in mesh_obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = rig
    kw = dict(filepath=path, export_format='GLB', use_selection=True, export_yup=True, export_materials='EXPORT', export_def_bones=True,
              export_apply=False)
    if animations:
        kw.update(export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True, export_optimize_animation_size=False)
    else:
        kw.update(export_animations=False)
    bpy.ops.export_scene.gltf(**kw)
    return path


def _bbox(objs):
    mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != 'MESH':
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    return mn, mx


def render_view(path, azimuth_deg, size=384, silhouette=False, elev_deg=8, bg=(0.82, 0.88, 0.95)):
    """Orthographic Workbench render from an azimuth (0 = front, 90 = the character's left side, 180 = back).
    silhouette=True renders a flat black shape on white (what the outline check compares)."""
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.render.resolution_x = size; sc.render.resolution_y = size
    sc.render.image_settings.file_format = 'PNG'
    sc.render.film_transparent = False
    sh = sc.display.shading
    if silhouette:
        sh.light = 'FLAT'; sh.color_type = 'SINGLE'; sh.single_color = (0, 0, 0)
        sh.show_object_outline = False; sh.show_specular_highlight = False
        bgc = (1, 1, 1)
    else:
        sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_object_outline = True; sh.show_specular_highlight = True
        bgc = bg
    sh.show_cavity = False
    if sc.world is None:
        sc.world = bpy.data.worlds.new('pw')
    sc.world.color = bgc
    # the Workbench background uses the world colour in "flat" mode
    sc.display.shading.background_type = 'WORLD'
    mn, mx = _bbox(bpy.data.objects)
    center = (mn + mx) / 2
    span = max((mx - mn).x, (mx - mn).y, (mx - mn).z, 0.1)
    cam = bpy.data.objects.get('pn_cam')
    if cam is None:
        cam = bpy.data.objects.new('pn_cam', bpy.data.cameras.new('pn_cam'))
        bpy.context.scene.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = span * 1.25
    a, e = math.radians(azimuth_deg), math.radians(elev_deg)
    dist = span * 4
    # the character faces +Y: azimuth 0 = looking at its face (camera on +Y), 90 = from its left (-X)
    cam.location = center + Vector((-math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e))) * dist
    cam.rotation_euler = (center - cam.location).to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sc.render.filepath = os.path.abspath(path)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    return path


def contact_sheet(paths, out, size=384):
    """Place the view PNGs side by side in ONE image (the review sheet)."""
    imgs = [bpy.data.images.load(p) for p in paths]
    w = size * len(imgs)
    sheet = bpy.data.images.new('pn_sheet', w, size)
    buf = [0.0] * (w * size * 4)
    for i, im in enumerate(imgs):
        px = list(im.pixels)
        for y in range(size):
            row = px[y * size * 4:(y + 1) * size * 4]
            buf[(y * w + i * size) * 4:(y * w + (i + 1) * size) * 4] = row
    sheet.pixels = buf
    sheet.filepath_raw = os.path.abspath(out)
    sheet.file_format = 'PNG'
    sheet.save()
    for im in imgs:
        bpy.data.images.remove(im)
    bpy.data.images.remove(sheet)
    return out
