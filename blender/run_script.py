"""Driver run by `playpen-model run <script.py>` INSIDE Blender: runs Claude's script, exports a .glb if the script did not, renders a preview."""
import sys, os, json, runpy
here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import bpy
import pn_blender as pb

argv = sys.argv[sys.argv.index('--') + 1:]
script, out_glb, out_png = argv[0], argv[1], argv[2]
os.environ['PLAYPEN_OUT_GLB'] = out_glb
os.environ['PLAYPEN_OUT_PNG'] = out_png
pb.reset_scene()
runpy.run_path(script, run_name='__main__')   # the script does `import pn_blender as pb` and builds geometry
if not os.path.exists(out_glb):
    pb.export_glb(out_glb, animations=bool(bpy.data.actions))
if not os.path.exists(out_png):
    pb.render_preview(out_png)
s = pb.stats()
s.update({'glb': out_glb, 'preview': out_png})
print('PLAYPEN_MODEL_RESULT ' + json.dumps(s))
