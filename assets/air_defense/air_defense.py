# air_defense.py — ПВО «миниган» в лего-стиле по референс-скрину (Blender, bpy).
#
# Как запустить: Blender → Scripting → вставить файл → Run Script (Alt+P)
# Или из консоли:  blender -b --factory-startup -P air_defense.py
#
# Конструкция (как на скрине): тёмный круглый барабан-основание с шипами,
# серый бронированный пьедестал с жёлтой окантовкой и X-раскосами, оливковая
# бронебашня с панелями и шипами, и шестиствольный блок минигана.
#
# ТРИ ЧАСТИ с разными пивотами (для анимации в игре):
#   BASE_  — статичное основание (низ на z=0)
#   HEAD_  — башня, крутится по yaw/pitch (пивот HEAD_PIVOT)
#   BARR_  — блок стволов, вращается при стрельбе (пивот BARREL_PIVOT)
# Стволы смотрят на -Y (в Roblox это -Z, то есть LookVector — ноль поправок).
#
# Единицы: 1 юнит = 1 стад. Blender 4.x.

import bpy
import os
import math
from math import radians
from mathutils import Vector

# Пивоты (их же использует bake_export.py и Config.AIR_DEFENSE в игре)
BASE_TOP = 6.7          # верх пьедестала
HEAD_PIVOT = (0.0, 0.0, 8.1)     # центр вращения башни
BARREL_PIVOT = (0.0, -4.6, 8.1)  # ось вращения блока стволов
TOTAL_H = 11.6

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def make_mat(name, color, rough=0.55, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    return m


MAT_GRAPHITE = make_mat("Graphite", (0.09, 0.095, 0.105), rough=0.6, metallic=0.3)
MAT_STEEL    = make_mat("Steel", (0.45, 0.47, 0.49), rough=0.45, metallic=0.5)
MAT_STEEL_D  = make_mat("SteelDark", (0.28, 0.30, 0.32), rough=0.5, metallic=0.5)
MAT_OLIVE    = make_mat("Olive", (0.33, 0.35, 0.18), rough=0.7)
MAT_OLIVE_D  = make_mat("OliveDark", (0.24, 0.26, 0.13), rough=0.7)
MAT_YELLOW   = make_mat("Yellow", (0.95, 0.78, 0.08), rough=0.5)
MAT_BLACK    = make_mat("Black", (0.04, 0.045, 0.05), rough=0.5)
MAT_GROUND   = make_mat("GroundMat", (0.35, 0.62, 0.28), rough=1.0)


def box(name, size, loc, mat, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=2, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    if rot:
        o.rotation_euler = rot
    o.data.materials.append(mat)
    return o


def cyl(name, r, depth, loc, mat, rot=None, verts=24):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=verts)
    o = bpy.context.object
    o.name = name
    if rot:
        o.rotation_euler = rot
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def stud(name, x, y, z, mat, r=0.32, h=0.22):
    return cyl(name, r, h, (x, y, z + h / 2), mat, verts=10)

# ----------------------------------------------------------------------------
# BASE_ — барабан + пьедестал
# ----------------------------------------------------------------------------
cyl("BASE_Drum", 4.3, 2.4, (0, 0, 1.2), MAT_GRAPHITE, verts=28)
cyl("BASE_DrumCap", 4.05, 0.35, (0, 0, 2.55), MAT_STEEL_D, verts=28)
for i in range(10):
    a = radians(36 * i)
    stud("BASE_Stud_%d" % i, math.cos(a) * 3.3, math.sin(a) * 3.3, 2.72, MAT_GRAPHITE)

# Пьедестал
box("BASE_Pedestal", (6.2, 6.2, 3.6), (0, 0, 2.7 + 1.8), MAT_STEEL)
# Жёлтая окантовка верхней кромки (перед/зад перекрывают углы)
for sx, sy, w, d in ((0, 3.0, 6.9, 0.5), (0, -3.0, 6.9, 0.5), (3.0, 0, 0.5, 5.7), (-3.0, 0, 0.5, 5.7)):
    box("BASE_Trim_%d_%d" % (sx * 10, sy * 10), (w, d, 0.4), (sx, sy, 6.1), MAT_YELLOW)
# X-раскосы на передней и задней гранях (не торчат за пьедестал)
for fy in (-3.18, 3.18):
    box("BASE_BraceA_%d" % int(fy * 10), (6.6, 0.3, 0.7), (0, fy, 4.5), MAT_STEEL_D, rot=(0, radians(33), 0))
    box("BASE_BraceB_%d" % int(fy * 10), (6.6, 0.3, 0.7), (0, fy, 4.5), MAT_STEEL_D, rot=(0, radians(-33), 0))
# Болты по углам пьедестала
for bx in (-2.6, 2.6):
    for by in (-2.6, 2.6):
        cyl("BASE_Bolt_%d_%d" % (bx * 10, by * 10), 0.22, 0.3, (bx, by, 6.28), MAT_GRAPHITE, verts=8)
# Верхняя плита-погон, на которой сидит башня
cyl("BASE_Ring", 2.8, 0.7, (0, 0, 6.45), MAT_GRAPHITE, verts=24)

# ----------------------------------------------------------------------------
# HEAD_ — бронебашня (пивот HEAD_PIVOT)
# ----------------------------------------------------------------------------
hz = HEAD_PIVOT[2]
box("HEAD_Body", (6.4, 7.0, 3.2), (0, 0.4, hz), MAT_OLIVE)
# Утопленные панели по бокам и спереди
for px in (-3.28, 3.28):
    box("HEAD_PanelSide_%d" % int(px * 10), (0.18, 4.4, 2.0), (px, 0.5, hz), MAT_OLIVE_D)
box("HEAD_PanelFront", (4.4, 0.18, 1.8), (0, -3.18, hz), MAT_OLIVE_D)
# Шипы сверху (2x3, крупные)
for ix in range(2):
    for iy in range(3):
        stud("HEAD_Stud_%d_%d" % (ix, iy), -1.0 + ix * 2.0, -1.2 + iy * 1.8, hz + 1.6, MAT_OLIVE, r=0.5, h=0.28)
# Жёлтые акценты на передних верхних углах
box("HEAD_TrimL", (1.6, 0.5, 0.4), (-2.3, -3.1, hz + 1.5), MAT_YELLOW)
box("HEAD_TrimR", (1.6, 0.5, 0.4), (2.3, -3.1, hz + 1.5), MAT_YELLOW)
# Ящик боекомплекта справа + крышка
box("HEAD_Ammo", (1.7, 3.6, 2.3), (3.9, 0.6, hz - 0.2), MAT_OLIVE_D)
box("HEAD_AmmoLid", (1.8, 3.7, 0.3), (3.9, 0.6, hz + 1.05), MAT_OLIVE)
# Вентиляционные жалюзи сзади
for k in range(3):
    box("HEAD_Vent_%d" % k, (4.6, 0.25, 0.42), (0, 3.95, hz - 0.9 + k * 0.85), MAT_OLIVE_D)
# Антенна слева
cyl("HEAD_Antenna", 0.10, 2.6, (-3.5, 1.6, hz + 2.6), MAT_STEEL_D, verts=8)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.26, location=(-3.5, 1.6, hz + 3.95), segments=10, ring_count=6)
_ant = bpy.context.object
_ant.name = "HEAD_AntennaTip"
_ant.data.materials.append(MAT_YELLOW)
bpy.ops.object.shade_smooth()
# Хомут-кронштейн, из которого выходит блок стволов
box("HEAD_Mount", (2.6, 1.6, 2.2), (0, -3.9, hz), MAT_STEEL_D)

# ----------------------------------------------------------------------------
# BARR_ — шестиствольный блок (пивот BARREL_PIVOT, стволы вдоль -Y)
# ----------------------------------------------------------------------------
by0 = BARREL_PIVOT[1]
bz = BARREL_PIVOT[2]
BARREL_LEN = 6.6
# Задний хаб
cyl("BARR_Hub", 1.25, 1.4, (0, by0 - 0.5, bz), MAT_GRAPHITE, rot=(radians(90), 0, 0), verts=20)
# Центральный вал
cyl("BARR_Shaft", 0.45, BARREL_LEN - 1.0, (0, by0 - 1.2 - (BARREL_LEN - 1.0) / 2, bz), MAT_STEEL_D, rot=(radians(90), 0, 0), verts=12)
# Шесть стволов вокруг вала
for i in range(6):
    a = radians(60 * i)
    ox = math.cos(a) * 0.78
    oz = math.sin(a) * 0.78
    cyl("BARR_Tube_%d" % i, 0.27, BARREL_LEN, (ox, by0 - 1.2 - BARREL_LEN / 2, bz + oz), MAT_STEEL, rot=(radians(90), 0, 0), verts=10)
# Среднее кольцо-обойма и дульный блок
cyl("BARR_MidRing", 1.18, 0.55, (0, by0 - 1.2 - BARREL_LEN * 0.55, bz), MAT_STEEL_D, rot=(radians(90), 0, 0), verts=20)
cyl("BARR_Muzzle", 1.08, 1.0, (0, by0 - 1.2 - BARREL_LEN + 0.3, bz), MAT_GRAPHITE, rot=(radians(90), 0, 0), verts=20)
cyl("BARR_MuzzleHole", 0.62, 0.25, (0, by0 - 1.2 - BARREL_LEN - 0.22, bz), MAT_BLACK, rot=(radians(90), 0, 0), verts=16)

# Приподнимем блок стволов, как на скрине (лёгкий задир вверх) — только превью:
# в игре pitch задаёт код. Держим оси чистыми, БЕЗ поворота.

# ----------------------------------------------------------------------------
# Земля для превью (в игру не едет)
# ----------------------------------------------------------------------------
box("Ground", (30, 30, 0.3), (0, 0, -0.15), MAT_GROUND)

# ----------------------------------------------------------------------------
# Камера, солнце, мир
# ----------------------------------------------------------------------------
bpy.ops.object.camera_add(location=(17.5, -21.0, 11.5))
cam = bpy.context.object
cam.rotation_euler = (Vector((-0.6, -2.4, 6.2)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 38
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(0, 0, 20))
sun = bpy.context.object
sun.rotation_euler = (radians(50), 0, radians(30))
sun.data.energy = 3.2
sun.data.angle = radians(4)

world = bpy.data.worlds.new("PvoWorld")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.62, 0.80, 1.0)

scene = bpy.context.scene
scene.render.resolution_x = 1000
scene.render.resolution_y = 800
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'

print("AIR DEFENSE built: BASE_TOP=%.1f HEAD_PIVOT=%s BARREL_PIVOT=%s TOTAL_H=%.1f"
      % (BASE_TOP, HEAD_PIVOT, BARREL_PIVOT, TOTAL_H))
