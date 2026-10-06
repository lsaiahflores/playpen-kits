"""Driver run by `playpen-model preview <model.glb>` INSIDE Blender: imports a .glb and renders a preview PNG."""
import sys, os, json
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import bpy
import pn_blender as pb

argv = sys.argv[sys.argv.index('--') + 1:]
pb.reset_scene()
bpy.ops.import_scene.gltf(filepath=argv[0])
pb.render_preview(argv[1])
print('PLAYPEN_MODEL_RESULT ' + json.dumps(pb.stats()))
