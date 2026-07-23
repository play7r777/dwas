# bake_export.py — готовит пиццерию к импорту в игру:
#   1) строит сцену из pizza_shop.py (уровень чистоты — env PIZZA_LEVEL, 1..5)
#   2) объединяет здание в ОДИН меш, центрирует в origin (низ на z=0)
#   3) UV-развёртка + запекание всех процедурных материалов в атлас 2048px
#   4) экспорт OBJ + MTL + PNG (можно сразу тащить в Roblox Studio → Import 3D)
#   5) (опционально, env BAKE_CHECK=1) контрольный рендер запечённой модели
#
# Запуск: PIZZA_LEVEL=3 blender -b --factory-startup -P bake_export.py
import bpy
import os
from math import radians
from mathutils import Vector, Matrix

EXPORT_DIR = "/agent/workspace/export"
os.makedirs(EXPORT_DIR, exist_ok=True)

exec(open("/agent/workspace/pizza_shop.py", encoding="utf-8").read())
LVL = LEVEL  # выставлен внутри pizza_shop.py из PIZZA_LEVEL

# --- Убираем окружение (земля/тротуар в игру не едут) ---
for name in ("Ground", "Sidewalk"):
    obj = bpy.data.objects.get(name)
    if obj:
        bpy.data.objects.remove(obj, do_unlink=True)

# --- Текст PIZZA -> меш ---
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
shop.name = "PizzaShop"
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
img = bpy.data.images.new("PizzaShopAtlas_lvl%d" % LVL, 2048, 2048)
for mat in shop.data.materials:
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = img
    nodes.active = tex

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 8
bpy.ops.object.select_all(action='DESELECT')
shop.select_set(True)
bpy.context.view_layer.objects.active = shop
bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=4)

tex_path = os.path.join(EXPORT_DIR, "pizza_shop_lvl%d_texture.png" % LVL)
img.filepath_raw = tex_path
img.file_format = 'PNG'
img.save()
print("BAKED:", tex_path)

# --- Один финальный материал с запечённой текстурой ---
baked = bpy.data.materials.new("PizzaShopBaked_lvl%d" % LVL)
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
obj_path = os.path.join(EXPORT_DIR, "pizza_shop_lvl%d.obj" % LVL)
bpy.ops.wm.obj_export(
    filepath=obj_path,
    export_selected_objects=True,
    export_materials=True,
    path_mode='COPY',
)
print("EXPORTED:", obj_path)

if os.environ.get("BAKE_CHECK", "0") != "1":
    print("BAKE EXPORT DONE")
    raise SystemExit(0)

# --- Контрольный рендер запечённой модели (чистая сцена + импорт OBJ) ---
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.obj_import(filepath=obj_path)

bpy.ops.object.camera_add(location=(7.2, -9.8, 3.7))
cam = bpy.context.object
cam.rotation_euler = (Vector((-0.6, -0.6, 2.1)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 33
bpy.context.scene.camera = cam
bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
sun = bpy.context.object
sun.rotation_euler = (radians(55), 0, radians(15))
sun.data.energy = 3.2
world = bpy.data.worlds.new("W")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.55, 0.68, 1.0)

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 48
scene.cycles.use_denoising = True
scene.render.resolution_x = 1000
scene.render.resolution_y = 800
scene.render.filepath = os.path.join(EXPORT_DIR, "baked_check.png")
bpy.ops.render.render(write_still=True)
print("BAKE EXPORT DONE")
