# bake_export.py — готовит КАФЕ к импорту в игру (тот же конвейер, что у пиццерии):
#   1) строит сцену из cafe.py (уровень чистоты — env CAFE_LEVEL, 1..5)
#   2) (env PREVIEW=1) рендерит превью сцены в preview_lvlN.png
#   3) объединяет здание в ОДИН меш, центрирует в origin (низ на z=0)
#   4) UV-развёртка + запекание всех процедурных материалов в атлас 2048px
#   5) экспорт OBJ + MTL + PNG рядом со скриптом (Roblox Studio → Import 3D)
#
# Запуск: CAFE_LEVEL=3 PREVIEW=1 blender -b --factory-startup -P bake_export.py
import bpy
import os
from math import radians
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT_DIR = os.environ.get("EXPORT_DIR", HERE)
os.makedirs(EXPORT_DIR, exist_ok=True)

exec(open(os.path.join(HERE, "cafe.py"), encoding="utf-8").read())
LVL = LEVEL  # выставлен внутри cafe.py из CAFE_LEVEL

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'

# --- (опция) превью полной сцены до разборки ---
if os.environ.get("PREVIEW", "0") == "1":
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 960
    scene.render.resolution_y = 760
    scene.render.filepath = os.path.join(EXPORT_DIR, "preview_lvl%d.png" % LVL)
    bpy.ops.render.render(write_still=True)
    print("PREVIEW:", scene.render.filepath)

# --- Убираем окружение (земля/тротуар в игру не едут) ---
for name in ("Ground", "Sidewalk"):
    obj = bpy.data.objects.get(name)
    if obj:
        bpy.data.objects.remove(obj, do_unlink=True)

# --- Текст CAFE -> меш ---
for obj in list(bpy.data.objects):
    if obj.type == 'FONT':
        bpy.ops.object.select_all(action='DESELECT')
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.convert(target='MESH')

# --- Джойним все меши в один объект ---
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
shop = bpy.context.object
shop.name = "Cafe"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- Центрируем: XY-центр в origin, низ на z=0 ---
bb = [Vector(c) for c in shop.bound_box]
cx = (min(v.x for v in bb) + max(v.x for v in bb)) / 2
cy = (min(v.y for v in bb) + max(v.y for v in bb)) / 2
minz = min(v.z for v in bb)
shop.data.transform(Matrix.Translation((-cx, -cy, -minz)))

# --- UV-развёртка ---
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=radians(66), island_margin=0.003)
bpy.ops.object.mode_set(mode='OBJECT')

# --- Запекание цвета всех процедурных материалов в атлас ---
img = bpy.data.images.new("CafeAtlas_lvl%d" % LVL, 2048, 2048)
for mat in shop.data.materials:
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    nodes.active = tex

scene.cycles.samples = 4
bpy.ops.object.select_all(action='DESELECT')
shop.select_set(True)
bpy.context.view_layer.objects.active = shop
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=4)

tex_path = os.path.join(EXPORT_DIR, "cafe_lvl%d_texture.png" % LVL)
img.filepath_raw = tex_path
img.file_format = 'PNG'
img.save()
print("BAKED:", tex_path)

# --- Один финальный материал с запечённой текстурой ---
baked = bpy.data.materials.new("CafeBaked_lvl%d" % LVL)
baked.use_nodes = True
bnodes = baked.node_tree.nodes
blinks = baked.node_tree.links
bsdf = bnodes["Principled BSDF"]
bsdf.inputs["Roughness"].default_value = 0.85
btex = bnodes.new("ShaderNodeTexImage")
btex.image = img
blinks.new(btex.outputs["Color"], bsdf.inputs["Base Color"])
shop.data.materials.clear()
shop.data.materials.append(baked)

# --- Экспорт OBJ (+MTL, текстура копируется рядом) ---
obj_path = os.path.join(EXPORT_DIR, "cafe_lvl%d.obj" % LVL)
bpy.ops.wm.obj_export(
    filepath=obj_path,
    export_selected_objects=True,
    export_materials=True,
    path_mode='COPY',
)
tris = sum(len(p.vertices) - 2 for p in shop.data.polygons)
print("EXPORTED:", obj_path, "tris=%d" % tris)
print("BAKE EXPORT DONE")
