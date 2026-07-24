# bake_export.py — готовит ПВО к импорту в игру ТРЕМЯ частями:
#   env PVO_PART=base|head|barrels — какую часть экспортировать
#   env PREVIEW=1 — перед разборкой отрендерить превью всей турели
#
# Пивоты частей (для сборки/анимации в игре):
#   base    — низ на z=0 (как есть)
#   head    — HEAD_PIVOT переносится в origin (башня крутится вокруг origin)
#   barrels — BARREL_PIVOT переносится в origin (блок стволов вращается вокруг -Y...
#             в Roblox после импорта ось стволов = -Z, то есть LookVector)
#
# Запуск: PVO_PART=base PREVIEW=1 blender -b --factory-startup -P bake_export.py
#         PVO_PART=head blender -b --factory-startup -P bake_export.py
#         PVO_PART=barrels blender -b --factory-startup -P bake_export.py
import bpy
import os
from math import radians
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT_DIR = os.environ.get("EXPORT_DIR", HERE)
os.makedirs(EXPORT_DIR, exist_ok=True)

PART = os.environ.get("PVO_PART", "base").lower()
assert PART in ("base", "head", "barrels"), "PVO_PART: base|head|barrels"

exec(open(os.path.join(HERE, "air_defense.py"), encoding="utf-8").read())

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'

if os.environ.get("PREVIEW", "0") == "1":
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.filepath = os.path.join(EXPORT_DIR, "preview_air_defense.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW:", scene.render.filepath)

PREFIX = {"base": "BASE_", "head": "HEAD_", "barrels": "BARR_"}[PART]
PIVOT = {
    "base": (0.0, 0.0, 0.0),
    "head": HEAD_PIVOT,
    "barrels": BARREL_PIVOT,
}[PART]

for obj in list(bpy.data.objects):
    if obj.type == 'MESH' and not obj.name.startswith(PREFIX):
        bpy.data.objects.remove(obj, do_unlink=True)

meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
part = bpy.context.object
part.name = "AirDefense_" + PART
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- Пивот в origin ---
part.data.transform(Matrix.Translation((-PIVOT[0], -PIVOT[1], -PIVOT[2])))

# --- UV + запекание в атлас 1024 ---
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=radians(66), island_margin=0.003)
bpy.ops.object.mode_set(mode='OBJECT')

img = bpy.data.images.new("PvoAtlas_" + PART, 1024, 1024)
for mat in part.data.materials:
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    nodes.active = tex

scene.cycles.samples = 4
bpy.ops.object.select_all(action='DESELECT')
part.select_set(True)
bpy.context.view_layer.objects.active = part
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=4)

tex_path = os.path.join(EXPORT_DIR, "air_defense_%s_texture.png" % PART)
img.filepath_raw = tex_path
img.file_format = 'PNG'
img.save()
print("BAKED:", tex_path)

baked = bpy.data.materials.new("PvoBaked_" + PART)
baked.use_nodes = True
bsdf = baked.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.55
btex = baked.node_tree.nodes.new("ShaderNodeTexImage")
btex.image = img
baked.node_tree.links.new(btex.outputs["Color"], bsdf.inputs["Base Color"])
part.data.materials.clear()
part.data.materials.append(baked)

obj_path = os.path.join(EXPORT_DIR, "air_defense_%s.obj" % PART)
bpy.ops.wm.obj_export(
    filepath=obj_path,
    export_selected_objects=True,
    export_materials=True,
    path_mode='COPY',
)
tris = sum(len(p.vertices) - 2 for p in part.data.polygons)
print("EXPORTED:", obj_path, "tris=%d" % tris)
print("BAKE EXPORT DONE")
