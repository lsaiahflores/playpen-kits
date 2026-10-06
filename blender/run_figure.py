"""Driver run by `playpen-model figure <spec.json>` INSIDE Blender: builds a brick-toy figure, exports a .glb, renders a preview."""
import sys, os, json
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import bpy
import pn_blender as pb
import brick_figure as bf

argv = sys.argv[sys.argv.index('--') + 1:]
spec = json.loads(open(argv[0], 'r', encoding='utf-8').read())
out_glb = argv[1]
out_png = argv[2]
r = bf.build(spec)
pb.export_glb(out_glb, animations=True)
# preview: show the standing pose
bpy.context.scene.frame_set(1)
frame = spec.get('previewAction')
if frame and frame in bpy.data.actions:
    r['armature'].animation_data.action = bpy.data.actions[frame]
    bpy.context.scene.frame_set(int(spec.get('previewFrame', 8)))
pb.render_preview(out_png, size=int(spec.get('previewSize', 640)))
s = pb.stats()
s.update({'height_m': round(r['height'], 2), 'glb': out_glb, 'preview': out_png})
print('PLAYPEN_MODEL_RESULT ' + json.dumps(s))
