# export_obj.py — экспорт лего-островов в OBJ для Roblox (Import 3D):
#   env ISLAND=main → строит main_island.py, экспорт main_island.obj
#   env ISLAND=sub  → строит sub_island.py,  экспорт sub_island.obj
#   env PREVIEW=1   → перед экспортом рендерит превью сцены (с ракетами в зоне)
#
# Остров НЕ запекается в атлас: шипы держат ТАЙЛОВЫЕ текстуры tile_*.png
# (лежат рядом, генерируются самим генератором) — грид шипов остаётся чётким,
# а геометрия влезает в лимит Roblox по треугольникам.
#
# Запуск: ISLAND=main PREVIEW=1 blender -b --factory-startup -P export_obj.py
import bpy
import os
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT_DIR = os.environ.get("EXPORT_DIR", HERE)
os.makedirs(EXPORT_DIR, exist_ok=True)

KIND = os.environ.get("ISLAND", "main")
assert KIND in ("main", "sub"), "ISLAND должен быть main или sub"
src = "main_island.py" if KIND == "main" else "sub_island.py"

exec(open(os.path.join(HERE, src), encoding="utf-8").read())

scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'

if os.environ.get("PREVIEW", "0") == "1":
    scene.cycles.samples = 32
    scene.cycles.use_denoising = True
    scene.render.filepath = os.path.join(EXPORT_DIR, "preview_%s_island.png" % KIND)
    bpy.ops.render.render(write_still=True)
    print("PREVIEW:", scene.render.filepath)

# --- Убираем превью-объекты (ракеты) — в экспорт они не идут ---
for obj in list(bpy.data.objects):
    if obj.type == 'MESH' and obj.name.startswith("PRV_"):
        bpy.data.objects.remove(obj, do_unlink=True)

# --- Джойним все части острова в один объект ---
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
isl = bpy.context.object
isl.name = "MainIsland" if KIND == "main" else "SubIsland"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- Центрируем: XY-центр в origin, НИЗ на z=0 (верх = высота меша) ---
bb = [Vector(c) for c in isl.bound_box]
cx = (min(v.x for v in bb) + max(v.x for v in bb)) / 2
cy = (min(v.y for v in bb) + max(v.y for v in bb)) / 2
minz = min(v.z for v in bb)
isl.data.transform(Matrix.Translation((-cx, -cy, -minz)))

obj_path = os.path.join(EXPORT_DIR, "%s_island.obj" % KIND)
bpy.ops.wm.obj_export(
    filepath=obj_path,
    export_selected_objects=True,
    export_materials=True,
    path_mode='RELATIVE',
)
tris = sum(len(p.vertices) - 2 for p in isl.data.polygons)
h = max(v.z for v in [Vector(c) for c in isl.bound_box])
print("EXPORTED:", obj_path, "tris=%d height=%.2f" % (tris, h))
print("EXPORT DONE")
