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

# --- Джойним все части острова в один объект... ---
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
isl = bpy.context.object
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- ...и РАЗРЕЗАЕМ ПО МАТЕРИАЛАМ на отдельные объекты. ---
# Roblox Import 3D не умеет мульти-материальный объект: MeshPart несёт ОДНУ
# текстуру, и весь остров заливался одним материалом (жёлтым). Один объект =
# один материал → Studio соберёт Model из MeshPart'ов, каждый со своей текстурой.
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.separate(type='MATERIAL')
bpy.ops.object.mode_set(mode='OBJECT')

parts = [o for o in bpy.data.objects if o.type == 'MESH']
for o in parts:
    if len(o.data.polygons) == 0:
        bpy.data.objects.remove(o, do_unlink=True)
        continue
    mat = o.data.materials[o.data.polygons[0].material_index]
    o.name = mat.name if mat else "part"

parts = [o for o in bpy.data.objects if o.type == 'MESH']

# --- Общее центрирование: XY-центр в origin, НИЗ на z=0 (верх = высота меша) ---
xs, ys, zs = [], [], []
for o in parts:
    for c in o.bound_box:
        v = o.matrix_world @ Vector(c)
        xs.append(v.x); ys.append(v.y); zs.append(v.z)
cx = (min(xs) + max(xs)) / 2
cy = (min(ys) + max(ys)) / 2
minz = min(zs)
for o in parts:
    o.data.transform(Matrix.Translation((-cx, -cy, -minz)))

obj_path = os.path.join(EXPORT_DIR, "%s_island.obj" % KIND)
bpy.ops.object.select_all(action='DESELECT')
for o in parts:
    o.select_set(True)
bpy.ops.wm.obj_export(
    filepath=obj_path,
    export_selected_objects=True,
    export_materials=True,
    path_mode='RELATIVE',
)
tris = sum(len(p.vertices) - 2 for o in parts for p in o.data.polygons)
h = max(zs) - minz
print("EXPORTED:", obj_path, "objects=%d tris=%d height=%.2f" % (len(parts), tris, h))

# --- Патчим MTL: Blender не пишет Kd при подключённой текстуре, а превью
# Roblox для ЦЕЛОЙ модели текстуры не применяет и без Kd рендерит тёмный
# монотон. Дописываем базовый цвет каждому материалу — превью становится
# цветным, на текстуры это не влияет. ---
MTL_KD = {
    "M_grass": (86, 165, 54), "M_sidewalk": (206, 208, 204),
    "M_asphalt": (62, 64, 68), "M_concrete": (148, 150, 149),
    "M_sand": (238, 192, 104), "M_sand2": (226, 176, 88),
    "M_f_green": (58, 122, 38), "M_f_sand": (216, 166, 82),
    "M_f_cliff": (196, 148, 70), "M_f_rock": (88, 90, 94),
    "M_f_gray": (168, 170, 168), "M_f_asphalt": (48, 50, 54),
    "M_f_black": (26, 27, 29), "M_f_yellow": (247, 200, 20),
}
mtl_path = obj_path[:-4] + ".mtl"
lines_out = []
for line in open(mtl_path, encoding="utf-8"):
    lines_out.append(line)
    if line.startswith("newmtl "):
        name = line.split()[1].strip()
        rgb = MTL_KD.get(name)
        if rgb:
            lines_out.append("Kd %.6f %.6f %.6f\n" % (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255))
with open(mtl_path, "w", encoding="utf-8") as f:
    f.writelines(lines_out)
print("MTL PATCHED:", mtl_path)
print("EXPORT DONE")
