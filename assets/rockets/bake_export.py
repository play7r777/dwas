# bake_export.py — готовит ЛЕГО-РАКЕТУ к импорту в игру:
#   1) строит сцену из rockets.py (все 4 марки в ряд)
#   2) (env PREVIEW=1) рендерит превью всех ракет в preview_rockets.png
#   3) оставляет ОДНУ марку (env ROCKET_MARK=1..4), джойнит, центрирует ось
#      в origin (низ на z=0)
#   4) UV-развёртка + запекание материалов в атлас 1024px
#   5) экспорт rocket_mkN.obj + MTL + PNG рядом со скриптом
#
# Запуск: ROCKET_MARK=1 PREVIEW=1 blender -b --factory-startup -P bake_export.py
import bpy
import os
from math import radians
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT_DIR = os.environ.get("EXPORT_DIR", HERE)
os.makedirs(EXPORT_DIR, exist_ok=True)

MARK = max(1, min(4, int(os.environ.get("ROCKET_MARK", "1"))))

exec(open(os.path.join(HERE, "rockets.py"), encoding="utf-8").read())

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'

if os.environ.get("PREVIEW", "0") == "1":
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.filepath = os.path.join(EXPORT_DIR, "preview_rockets.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW:", scene.render.filepath)

# --- Оставляем только выбранную марку ---
keep_prefix = "R%d_" % MARK
for obj in list(bpy.data.objects):
    if obj.type == 'MESH' and not obj.name.startswith(keep_prefix):
        bpy.data.objects.remove(obj, do_unlink=True)

meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
rocket = bpy.context.object
rocket.name = "RocketMk%d" % MARK
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- Центрируем: ось ракеты в origin, низ на z=0 ---
bb = [Vector(c) for c in rocket.bound_box]
cx = (min(v.x for v in bb) + max(v.x for v in bb)) / 2
cy = (min(v.y for v in bb) + max(v.y for v in bb)) / 2
minz = min(v.z for v in bb)
rocket.data.transform(Matrix.Translation((-cx, -cy, -minz)))

bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=radians(66), island_margin=0.003)
bpy.ops.object.mode_set(mode='OBJECT')

img = bpy.data.images.new("RocketAtlas_%d" % MARK, 1024, 1024)
for mat in rocket.data.materials:
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    nodes.active = tex

scene.cycles.samples = 4
bpy.ops.object.select_all(action='DESELECT')
rocket.select_set(True)
bpy.context.view_layer.objects.active = rocket
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=4)

tex_path = os.path.join(EXPORT_DIR, "rocket_mk%d_texture.png" % MARK)
img.filepath_raw = tex_path
img.file_format = 'PNG'
img.save()
print("BAKED:", tex_path)

baked = bpy.data.materials.new("RocketBaked_%d" % MARK)
baked.use_nodes = True
bsdf = baked.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.5
btex = baked.node_tree.nodes.new("ShaderNodeTexImage")
btex.image = img
baked.node_tree.links.new(btex.outputs["Color"], bsdf.inputs["Base Color"])
rocket.data.materials.clear()
rocket.data.materials.append(baked)

obj_path = os.path.join(EXPORT_DIR, "rocket_mk%d.obj" % MARK)
bpy.ops.wm.obj_export(
    filepath=obj_path,
    export_selected_objects=True,
    export_materials=True,
    path_mode='COPY',
)
tris = sum(len(p.vertices) - 2 for p in rocket.data.polygons)
print("EXPORTED:", obj_path, "tris=%d" % tris)
print("BAKE EXPORT DONE")
