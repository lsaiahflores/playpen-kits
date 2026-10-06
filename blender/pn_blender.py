"""
pn_blender — Playpen's headless Blender helpers (Part 7.1).

Run through `playpen-model` (never by hand). Everything here works in `blender --background` with no UI.

MODELING STANDARDS (read before writing a model script):
  * BEVEL every hard edge (width 0.02-0.04 at figure scale, 2 segments). A razor-sharp box reads as a gray primitive;
    a softly beveled one catches light like a real toy. Use bevel_box()/bevel_cyl(), not raw cubes.
  * Shade the big flat faces FLAT and the small bevel faces SMOOTH (done for you): crisp planes + soft highlights.
  * Real proportions, ONE material slot per color (plastic_material). Never one material for a whole model.
  * Keep it light for the Compatibility renderer: a figure is ~600-2500 triangles, a prop 200-1500.
  * Pivot at the FEET (bottom center), +Y up in Godot terms (this exporter converts), facing -Z in Godot terms.
    1 Blender unit = 1 metre. A standing human-scale figure is ~1.8 units tall.
  * Rigs: a simple armature, one bone per rigid part group, parts weighted 100% to their bone. Animations are named
    idle-loop, walk-loop, run-loop, jump, attack, hit, die (Godot imports a "-loop" suffix as looping).
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix, Euler


# ------------------------------------------------------------------ scene
def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.unit_settings.system = 'METRIC'
    return sc


def hex_rgba(h, a=1.0):
    h = h.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    # sRGB -> linear for Blender's Principled BSDF
    def lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(r), lin(g), lin(b), a)


_materials = {}


def plastic_material(name, color, gloss=0.85, emissive=0.0, metallic=0.0, rough=None):
    """Glossy toy plastic (a Principled BSDF with a clear coat). `emissive` > 0 makes it glow (visors, energy)."""
    key = (name, color)
    if key in _materials:
        return _materials[key]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = hex_rgba(color)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = rough if rough is not None else max(0.08, 0.55 - gloss * 0.45)
    for k, v in (('Specular IOR Level', 0.7), ('Coat Weight', gloss * 0.6), ('Coat Roughness', 0.08)):
        if k in bsdf.inputs:
            bsdf.inputs[k].default_value = v
    if emissive > 0:
        bsdf.inputs['Emission Color'].default_value = hex_rgba(color)
        bsdf.inputs['Emission Strength'].default_value = emissive
    m.diffuse_color = hex_rgba(color)  # what the Workbench preview shows
    _materials[key] = m
    return m


# ------------------------------------------------------------------ geometry (bmesh, no operators = reliable headless)
def _finish(name, bm, material, loc=(0, 0, 0), smooth_small=True, big_area=0.06):
    me = bpy.data.meshes.new(name)
    if smooth_small:
        for f in bm.faces:
            f.smooth = f.calc_area() < big_area
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = Vector(loc)
    if material is not None:
        ob.data.materials.append(material)
    return ob


def bevel_box(name, size, loc=(0, 0, 0), material=None, bevel=0.03, taper=1.0, segments=2):
    """A beveled box. size=(x,y,z) in metres; `taper` scales the TOP face (0.8 = narrower at the top)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
        if v.co.z > 0:
            v.co.x *= taper; v.co.y *= taper
    b = min(bevel, min(size) * 0.45)
    if b > 0.001:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=b, segments=segments, affect='EDGES', profile=0.6)
    return _finish(name, bm, material, loc)


def bevel_cyl(name, radius, depth, loc=(0, 0, 0), material=None, segments=20, bevel=0.015, r2=None, axis='Z'):
    """A beveled cylinder/cone (studs, heads, barrels). axis: 'Z' (up), 'X' or 'Y' lays it down."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=(r2 if r2 is not None else radius), depth=depth)
    if bevel > 0.001:
        rim = [e for e in bm.edges if abs(e.verts[0].co.z) > depth * 0.49 and abs(e.verts[1].co.z) > depth * 0.49]
        try:
            bmesh.ops.bevel(bm, geom=rim, offset=min(bevel, radius * 0.4, depth * 0.4), segments=2, affect='EDGES', profile=0.6)
        except Exception:
            pass
    if axis == 'X':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'Y'))
    elif axis == 'Y':
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, 'X'))
    # cylinders: caps flat, the round side smooth (no faceted 'knitted' look)
    for f in bm.faces:
        f.smooth = abs(f.normal.z) < 0.9 if axis == 'Z' else not (abs(f.normal.x) > 0.9 if axis == 'X' else abs(f.normal.y) > 0.9)
    return _finish(name, bm, material, loc, smooth_small=False)


def bevel_sphere(name, radius, loc=(0, 0, 0), material=None, scale=(1, 1, 1), u=20, v=12, top_only=False):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=u, v_segments=v, radius=radius)
    for vert in bm.verts:
        vert.co.x *= scale[0]; vert.co.y *= scale[1]; vert.co.z *= scale[2]
    if top_only:
        bmesh.ops.delete(bm, geom=[vv for vv in bm.verts if vv.co.z < -0.0001], context='VERTS')
        open_edges = [e for e in bm.edges if e.is_boundary]
        if open_edges:
            bmesh.ops.contextual_create(bm, geom=open_edges)
    for f in bm.faces:
        f.smooth = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.location = Vector(loc)
    if material is not None:
        ob.data.materials.append(material)
    return ob


def studs(name, count_x, count_y, spacing, radius, height, loc, material):
    """A grid of studs on top of a brick (the toy-brick signature). Returned as ONE object."""
    parts = []
    for ix in range(count_x):
        for iy in range(count_y):
            x = (ix - (count_x - 1) / 2) * spacing
            y = (iy - (count_y - 1) / 2) * spacing
            parts.append(bevel_cyl(f'{name}_{ix}_{iy}', radius, height, (loc[0] + x, loc[1] + y, loc[2] + height / 2), material, segments=14, bevel=height * 0.25))
    return join(parts, name) if parts else None


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    if len(objs) == 1:
        objs[0].name = name
        return objs[0]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    return ob


def set_origin_to_feet(ob):
    """Pivot at the bottom center (the feet)."""
    bpy.context.view_layer.update()
    mn = Vector((min((ob.matrix_world @ Vector(c)).x for c in ob.bound_box), min((ob.matrix_world @ Vector(c)).y for c in ob.bound_box), min((ob.matrix_world @ Vector(c)).z for c in ob.bound_box)))
    mx = Vector((max((ob.matrix_world @ Vector(c)).x for c in ob.bound_box), max((ob.matrix_world @ Vector(c)).y for c in ob.bound_box), max((ob.matrix_world @ Vector(c)).z for c in ob.bound_box)))
    cx, cy = (mn.x + mx.x) / 2, (mn.y + mx.y) / 2
    for v in ob.data.vertices:
        v.co.x -= cx - ob.location.x
        v.co.y -= cy - ob.location.y
        v.co.z -= mn.z - ob.location.z
    ob.location = (0, 0, 0)


# ------------------------------------------------------------------ rigging + animation
def make_armature(name, bones):
    """bones: list of (bone_name, parent_name|None, head(x,y,z), tail(x,y,z)). Returns the armature object."""
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    eb = {}
    for bname, parent, head, tail in bones:
        b = arm.edit_bones.new(bname)
        b.head = Vector(head); b.tail = Vector(tail)
        if parent:
            b.parent = eb[parent]
        eb[bname] = b
    bpy.ops.object.mode_set(mode='OBJECT')
    return ob


def weight_to_bone(ob, bone_name):
    vg = ob.vertex_groups.new(name=bone_name)
    vg.add(list(range(len(ob.data.vertices))), 1.0, 'REPLACE')


def skin(mesh_ob, armature_ob):
    mod = mesh_ob.modifiers.new('Armature', 'ARMATURE')
    mod.object = armature_ob
    mesh_ob.parent = armature_ob


def _pose_key(arm_ob, frame, pose):
    """pose: {bone: (rx, ry, rz) degrees} or {bone: (rx, ry, rz, (lx, ly, lz))}"""
    for bname, val in pose.items():
        pb = arm_ob.pose.bones[bname]
        pb.rotation_mode = 'XYZ'
        pb.rotation_euler = Euler(tuple(math.radians(a) for a in val[:3]), 'XYZ')
        pb.keyframe_insert('rotation_euler', frame=frame)
        if len(val) > 3:
            pb.location = Vector(val[3])
            pb.keyframe_insert('location', frame=frame)


def make_action(arm_ob, name, frames, fps=30, loop=False):
    """frames: list of (frame_number, pose_dict). Creates an action `name` on the armature and keeps it."""
    ad = arm_ob.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    ad.action = act
    bpy.context.view_layer.objects.active = arm_ob
    for f, pose in frames:
        _pose_key(arm_ob, f, pose)
    if loop:
        for fc in act.fcurves:
            fc.modifiers.new('CYCLES')
    bpy.context.scene.render.fps = fps
    ad.action = None
    return act


# ------------------------------------------------------------------ export + preview
def export_glb(path, animations=True):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    kw = dict(filepath=path, export_format='GLB', export_apply=False, export_yup=True, export_materials='EXPORT')
    if animations:
        kw.update(export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=True, export_optimize_animation_size=False)
    else:
        kw.update(export_animations=False)
    bpy.ops.export_scene.gltf(**kw)
    return path


def render_preview(path, size=640, target_height=None, angle_deg=35, elev_deg=14, ortho_scale=None):
    """Workbench preview (fast, works headless): studio light, material colors, outline."""
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.render.resolution_x = size; sc.render.resolution_y = size
    sc.render.image_settings.file_format = 'PNG'
    sc.render.film_transparent = False
    sh = sc.display.shading
    sh.light = 'STUDIO'; sh.color_type = 'MATERIAL'; sh.show_object_outline = True; sh.show_specular_highlight = True
    sh.show_cavity = False
    sc.world = bpy.data.worlds.new('pw') if sc.world is None else sc.world
    sc.world.color = (0.82, 0.88, 0.95)
    mn = Vector((1e9, 1e9, 1e9)); mx = Vector((-1e9, -1e9, -1e9))
    for o in bpy.data.objects:
        if o.type == 'MESH':
            for c in o.bound_box:
                w = o.matrix_world @ Vector(c)
                mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
                mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    center = (mn + mx) / 2
    span = max((mx - mn).x, (mx - mn).y, (mx - mn).z, 0.1)
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam'))
    bpy.context.scene.collection.objects.link(cam)
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = ortho_scale or span * 1.35
    a, e = math.radians(angle_deg), math.radians(elev_deg)
    dist = span * 4
    cam.location = center + Vector((math.sin(a) * math.cos(e), math.cos(a) * math.cos(e), math.sin(e))) * dist
    d = (center - cam.location)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sc.render.filepath = os.path.abspath(path)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    return path


def stats():
    tris = 0; meshes = 0
    for o in bpy.data.objects:
        if o.type == 'MESH':
            meshes += 1
            me = o.data
            me.calc_loop_triangles()
            tris += len(me.loop_triangles)
    return {'meshes': meshes, 'triangles': tris, 'materials': len(bpy.data.materials), 'actions': len(bpy.data.actions)}
