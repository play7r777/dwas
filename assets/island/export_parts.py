# export_parts.py — режет остров на ОТДЕЛЬНЫЕ OBJ-детали (как пальмы: один файл =
# один меш = ОДИН плоский цвет, БЕЗ текстур — нечему зависать в обработке Roblox).
#
#   ISLAND=main → island_grass / island_sand / island_sand_dark / island_rock /
#                 island_road / island_sidewalk / island_pad / island_marking /
#                 island_tape  (9 деталей)
#   ISLAND=sub  → sub_grass / sub_sand / sub_sand_dark / sub_rock  (4 детали)
#
# Все детали экспортируются В ОБЩИХ координатах острова (центр в origin, низ на
# z=0) и печатают МАНИФЕСТ: смещение bbox-центра каждой детали + габариты —
# эти числа лежат в Config.ISLAND.PIECES, по ним игра собирает остров обратно.
#
# Запуск: ISLAND=main blender -b --factory-startup -P export_parts.py
import bpy
import os
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT_DIR = os.environ.get("EXPORT_DIR", HERE)
os.makedirs(EXPORT_DIR, exist_ok=True)

KIND = os.environ.get("ISLAND", "main")
assert KIND in ("main", "sub")
src = "main_island.py" if KIND == "main" else "sub_island.py"

exec(open(os.path.join(HERE, src), encoding="utf-8").read())

# --- Убираем превью-объекты ---
for obj in list(bpy.data.objects):
    if obj.type == 'MESH' and obj.name.startswith("PRV_"):
        bpy.data.objects.remove(obj, do_unlink=True)

# --- Джойним всё и разрезаем по материалам ---
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.mesh.separate(type='MATERIAL')
bpy.ops.object.mode_set(mode='OBJECT')

mat_objs = {}
for o in [x for x in bpy.data.objects if x.type == 'MESH']:
    if len(o.data.polygons) == 0:
        bpy.data.objects.remove(o, do_unlink=True)
        continue
    m = o.data.materials[o.data.polygons[0].material_index]
    mat_objs[m.name if m else "none"] = mat_objs.get(m.name if m else "none", []) + [o]

# --- Семантические группы: имя детали → материалы + плоский цвет ---
if KIND == "main":
    GROUPS = [
        ("island_grass",     ["M_grass", "M_f_green"],   (86, 165, 54)),
        ("island_sand",      ["M_sand", "M_f_sand"],     (238, 192, 104)),
        ("island_sand_dark", ["M_sand2", "M_f_cliff"],   (222, 172, 86)),
        ("island_rock",      ["M_f_rock"],               (88, 90, 94)),
        ("island_road",      ["M_asphalt", "M_f_asphalt"], (62, 64, 68)),
        ("island_sidewalk",  ["M_sidewalk", "M_f_gray"], (206, 208, 204)),
        ("island_pad",       ["M_concrete"],             (148, 150, 149)),
        ("island_marking",   ["M_f_yellow"],             (247, 200, 20)),
        ("island_tape",      ["M_f_black"],              (26, 27, 29)),
    ]
else:
    GROUPS = [
        ("sub_grass",     ["M_grass", "M_f_green"], (86, 165, 54)),
        ("sub_sand",      ["M_sand", "M_f_sand"],   (238, 192, 104)),
        ("sub_sand_dark", ["M_sand2", "M_f_cliff"], (222, 172, 86)),
        ("sub_rock",      ["M_f_rock"],             (88, 90, 94)),
    ]

pieces = []
for name, mats, rgb in GROUPS:
    objs = []
    for m in mats:
        objs += mat_objs.get(m, [])
    if not objs:
        print("WARN: группа %s пуста" % name)
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    piece = bpy.context.view_layer.objects.active
    piece.name = name
    # ОДИН плоский материал без текстуры (экспортёр запишет Kd — Roblox покрасит)
    flat = bpy.data.materials.new("P_" + name)
    flat.use_nodes = True
    bsdf = flat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.6
    piece.data.materials.clear()
    piece.data.materials.append(flat)
    for p in piece.data.polygons:
        p.material_index = 0
    pieces.append(piece)

# --- Общее центрирование: XY-центр в origin, НИЗ на z=0 ---
xs, ys, zs = [], [], []
for o in pieces:
    for c in o.bound_box:
        v = o.matrix_world @ Vector(c)
        xs.append(v.x); ys.append(v.y); zs.append(v.z)
cx = (min(xs) + max(xs)) / 2
cy = (min(ys) + max(ys)) / 2
minz = min(zs)
for o in pieces:
    o.data.transform(Matrix.Translation((-cx, -cy, -minz)))

full_w = max(max(xs) - min(xs), max(ys) - min(ys))
full_h = max(zs) - minz

# --- Экспорт каждой детали отдельным OBJ + манифест ---
print("=== МАНИФЕСТ (%s): FULL_WIDTH=%.2f FULL_HEIGHT=%.2f ===" % (KIND, full_w, full_h))
for o in pieces:
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    path = os.path.join(EXPORT_DIR, o.name + ".obj")
    bpy.ops.wm.obj_export(
        filepath=path,
        export_selected_objects=True,
        export_materials=True,
        path_mode='RELATIVE',
    )
    bb = [Vector(c) for c in o.bound_box]  # локальные = мировые (transform применён)
    bx = (min(v.x for v in bb) + max(v.x for v in bb)) / 2
    by = (min(v.y for v in bb) + max(v.y for v in bb)) / 2
    bz = (min(v.z for v in bb) + max(v.z for v in bb)) / 2
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    # Смещение в координатах OBJ/Roblox: X=x, Y(вверх)=z, Z=-y
    print("PIECE %-18s off=Vector3.new(%8.3f, %7.3f, %8.3f)  tris=%d" % (o.name, bx, bz, -by, tris))
print("EXPORT PARTS DONE")
