# bake_export.py — готовит ЛЕГО-ПАЛЬМУ к импорту в игру:
#   1) строит сцену из palms.py (обе пальмы)
#   2) (env PREVIEW=1) рендерит превью обеих пальм в preview_palms.png
#   3) оставляет ОДНУ разновидность (env PALM_VARIANT=A|B), джойнит в один меш,
#      центрирует площадку в origin (низ на z=0)
#   4) UV-развёртка + запекание материалов в атлас 1024px
#   5) экспорт palm_a.obj / palm_b.obj + MTL + PNG рядом со скриптом
#
# Запуск: PALM_VARIANT=A PREVIEW=1 blender -b --factory-startup -P bake_export.py
#         PALM_VARIANT=B blender -b --factory-startup -P bake_export.py
import bpy
import os
from math import radians
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT_DIR = os.environ.get("EXPORT_DIR", HERE)
os.makedirs(EXPORT_DIR, exist_ok=True)

VARIANT = os.environ.get("PALM_VARIANT", "A").upper()
assert VARIANT in ("A", "B"), "PALM_VARIANT должен быть A или B"

exec(open(os.path.join(HERE, "palms.py"), encoding="utf-8").read())

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'

# --- (опция) превью обеих пальм ---
if os.environ.get("PREVIEW", "0") == "1":
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.filepath = os.path.join(EXPORT_DIR, "preview_palms.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW:", scene.render.filepath)

# --- Оставляем только выбранную разновидность ---
keep_prefix = "PA_" if VARIANT == "A" else "PB_"
for obj in list(bpy.data.objects):
    if obj.type == 'MESH' and not obj.name.startswith(keep_prefix):
        bpy.data.objects.remove(obj, do_unlink=True)

# --- Джойним в один объект ---
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
palm = bpy.context.object
palm.name = "Palm" + VARIANT
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- Центрируем ПО ПЛОЩАДКЕ (не по кроне): XY-центр площадки в origin, низ на z=0.
plate_center = None
minz = None
bb = [Vector(c) for c in palm.bound_box]
minz = min(v.z for v in bb)
# Площадка 4х4 стояла в origin построения — найдём её низ по вершинам с z ~ minz
xs, ys = [], []
for v in palm.data.vertices:
    if v.co.z < minz + 0.5:
        xs.append(v.co.x)
        ys.append(v.co.y)
cx = (min(xs) + max(xs)) / 2
cy = (min(ys) + max(ys)) / 2
palm.data.transform(Matrix.Translation((-cx, -cy, -minz)))

# --- UV-развёртка ---
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=radians(66), island_margin=0.003)
bpy.ops.object.mode_set(mode='OBJECT')

# --- Запекание в атлас 1024 ---
img = bpy.data.images.new("PalmAtlas_%s" % VARIANT, 1024, 1024)
for mat in palm.data.materials:
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    nodes.active = tex

scene.cycles.samples = 4
bpy.ops.object.select_all(action='DESELECT')
palm.select_set(True)
bpy.context.view_layer.objects.active = palm
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=4)

suffix = "a" if VARIANT == "A" else "b"
tex_path = os.path.join(EXPORT_DIR, "palm_%s_texture.png" % suffix)
img.filepath_raw = tex_path
img.file_format = 'PNG'
img.save()
print("BAKED:", tex_path)

baked = bpy.data.materials.new("PalmBaked_%s" % VARIANT)
baked.use_nodes = True
bnodes = baked.node_tree.nodes
bsdf = bnodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.8
btex = bnodes.new("ShaderNodeTexImage")
btex.image = img
baked.node_tree.links.new(btex.outputs["Color"], bsdf.inputs["Base Color"])
palm.data.materials.clear()
palm.data.materials.append(baked)

obj_path = os.path.join(EXPORT_DIR, "palm_%s.obj" % suffix)
bpy.ops.wm.obj_export(
    filepath=obj_path,
    export_selected_objects=True,
    export_materials=True,
    path_mode='COPY',
)
tris = sum(len(p.vertices) - 2 for p in palm.data.polygons)
print("EXPORTED:", obj_path, "tris=%d" % tris)
print("BAKE EXPORT DONE")
