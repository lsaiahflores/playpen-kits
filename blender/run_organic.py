"""Driver run by `playpen-model creature <spec.json>` INSIDE Blender: builds an organic, Rigify-rigged, animated character from a body base.
   argv after '--':  spec.json  out.glb  preview.png  review_dir
   spec: { base, name, colors{primary,secondary,accent,skin,visor,dark}, opts{scale,bulk,head,shoulders,legs,arms},
           regions{group: colorKey}, parts[{part, ...kwargs}], previewSize, targetTris }"""
import sys, os, json, math, time
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import bpy
import pn_blender as pb
import pn_organic as po
import bases
import parts as P
import animations

argv = sys.argv[sys.argv.index('--') + 1:]
spec_in = json.loads(open(argv[0], 'r', encoding='utf-8').read())
out_glb, out_png, review_dir = argv[1], argv[2], argv[3]
t0 = time.time()

DEFAULT_COLORS = {'primary': '#4f7f3a', 'secondary': '#3b4a2f', 'accent': '#d9c58a', 'skin': '#7a8f4a', 'visor': '#ffb627', 'dark': '#2a2d26'}
DEFAULT_PARTS = {
    'chunky-humanoid': [{'part': 'helmet', 'kind': 'visor'}, {'part': 'visor'}, {'part': 'shoulder_pads'}, {'part': 'chest_plate'}, {'part': 'boots'}, {'part': 'gauntlets'}],
    'hunched-digitigrade': [{'part': 'eyes'}, {'part': 'jaw', 'kind': 'mandibles'}, {'part': 'crest', 'kind': 'spikes'}, {'part': 'claws'}, {'part': 'tail_spike'}],
    'small-stocky': [{'part': 'helmet', 'kind': 'dome'}, {'part': 'eyes'}, {'part': 'backpack'}, {'part': 'boots'}],
    'tall-lanky': [{'part': 'eyes'}, {'part': 'crest', 'kind': 'horns'}, {'part': 'shoulder_pads', 'size': 0.8}, {'part': 'claws'}],
    'quadruped': [{'part': 'eyes'}, {'part': 'crest', 'kind': 'horns'}, {'part': 'tail_spike'}],
    'flyer': [{'part': 'eyes'}, {'part': 'jaw', 'kind': 'beak'}, {'part': 'wings'}, {'part': 'crest', 'kind': 'fin'}],
}
DEFAULT_REGIONS = {
    'chunky-humanoid': {'torso': 'secondary', 'head': 'skin', 'arms': 'secondary', 'hands': 'dark', 'legs': 'secondary', 'feet': 'dark'},
    'hunched-digitigrade': {'torso': 'skin', 'head': 'skin', 'arms': 'skin', 'hands': 'accent', 'legs': 'skin', 'feet': 'accent'},
    'small-stocky': {'torso': 'primary', 'head': 'skin', 'arms': 'skin', 'hands': 'skin', 'legs': 'secondary', 'feet': 'dark'},
    'tall-lanky': {'torso': 'dark', 'head': 'skin', 'arms': 'skin', 'hands': 'accent', 'legs': 'dark', 'feet': 'accent'},
    'quadruped': {'body': 'skin', 'head': 'skin', 'legs': 'skin', 'feet': 'accent', 'tail': 'secondary'},
    'flyer': {'torso': 'skin', 'head': 'skin', 'arms': 'secondary', 'hands': 'accent', 'legs': 'accent', 'feet': 'accent'},
}

cols = dict(DEFAULT_COLORS)
cols.update(spec_in.get('colors') or {})
base = bases.get_base(spec_in.get('base', 'chunky-humanoid'), spec_in.get('opts') or {})
name = spec_in.get('name') or base['id']

pb.reset_scene()
po.enable_rigify()

# 1. organic body: skin modifier + metaball bulk -> fused, remeshed, smoothed, decimated
skin = po.skin_body(name + '_skin', base['nodes'], base['edges'], subdiv=2)
blobs = []
if base.get('blobs'):
    blobs.append(po.metaball_blob(name + '_bulk', base['blobs']))
# colour regions are painted on the HIGH-resolution surface (smooth boundaries), then the mesh is decimated with them
mats = {k: pb.plastic_material('c_' + k, v, gloss=0.55) for k, v in cols.items()}
reg = dict(DEFAULT_REGIONS.get(base['id'], {}))
reg.update(spec_in.get('regions') or {})
body = po.fuse_and_smooth([skin] + blobs, name + '_body', voxel=0.03 * max(0.5, base['scale']) ** 0.5, target_tris=int(spec_in.get('targetTris', 5200)),
                          paint=lambda ob: po.paint_regions(ob, base['nodes'], base['edges'], {g: mats[c] for g, c in reg.items() if c in mats}, mats['skin']))

# 3. rig: Rigify metarig fitted to the SAME joints, generated, weights from the deform bones
meta = po.fit_metarig(base['kind'], base['joints'], base['bone_map'], delete=base.get('delete', ()))
rig = po.generate_rig(meta)
rig.name = name + '_rig'
po.weight_to_bones(body, rig)

# 4. hard-surface parts
objs = [body]
plist = spec_in.get('parts') if spec_in.get('parts') is not None else DEFAULT_PARTS.get(base['id'], [])
for item in plist:
    item = dict(item)
    fn = P.PARTS.get(item.pop('part', ''))
    if not fn:
        continue
    for made in fn(base, cols, **item):
        ob = made['obj']
        key = made.get('bone')
        defname = base['attach'].get(key) if key else None
        if made.get('skinned') or not defname or defname not in rig.data.bones:
            po.weight_to_bones(ob, rig)
        else:
            po.weight_part(ob, rig, defname)
        objs.append(ob)

# 5. one skinned mesh
mesh = pb.join(objs, name + '_mesh') if len(objs) > 1 else body
mesh.name = name + '_mesh'
po.bind(mesh, rig)
for p in mesh.data.polygons:
    p.use_smooth = True
bpy.context.view_layer.update()

# 6. animations
acts = animations.bake_all(rig, base)

# 7. export (deform bones only) + review renders
po.export_character(out_glb, rig, [mesh], animations=True)
mn, mx = po._bbox([mesh])   # measured in the REST pose (the pose renders below leave the rig mid-animation)
os.makedirs(review_dir, exist_ok=True)
views = [('front', 0), ('side', 90), ('back', 180), ('threequarter', 35)]
pngs = []
po.reset_pose(rig)
for vname, az in views:
    p = os.path.join(review_dir, vname + '.png')
    po.render_view(p, az, size=320)
    pngs.append(p)
sheet = po.contact_sheet(pngs, os.path.join(review_dir, 'review.png'), size=320)
sil = {}
for az in range(0, 360, 45):
    p = os.path.join(review_dir, 'sil_%03d.png' % az)
    po.render_view(p, az, size=256, silhouette=True, elev_deg=4)
    sil[str(az)] = p
po.render_view(out_png, 35, size=int(spec_in.get('previewSize', 640)))
# animation sanity: three poses rendered from the side (walk mid-stride, attack strike, die) so a broken rig is SEEN, not assumed
pose_pngs = []
for aname, frame in (('walk-loop', 7), ('attack', 9), ('die', 26)):
    if aname in bpy.data.actions:
        rig.animation_data_create().action = bpy.data.actions[aname]
        bpy.context.scene.frame_set(frame)
        bpy.context.view_layer.update()
        pp = os.path.join(review_dir, 'pose_' + aname.replace('-loop', '') + '.png')
        po.render_view(pp, 90, size=320)
        pose_pngs.append(pp)
if pose_pngs:
    po.contact_sheet(pose_pngs, os.path.join(review_dir, 'poses.png'), size=320)
rig.animation_data.action = None

s = pb.stats()
s.update({'base': base['id'], 'nonHuman': base['nonhuman'], 'height_m': round(mx.z - mn.z, 2), 'width_m': round(mx.x - mn.x, 2), 'depth_m': round(mx.y - mn.y, 2), 'floor_z': round(mn.z, 3),
          'animations': acts, 'bones_exported': sum(1 for b in rig.data.bones if b.use_deform), 'glb': out_glb, 'preview': out_png, 'review': sheet, 'silhouettes': sil,
          'seconds': round(time.time() - t0, 1), 'parts': [i.get('part') for i in plist]})
print('PLAYPEN_MODEL_RESULT ' + json.dumps(s))
