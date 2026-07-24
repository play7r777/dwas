# palms.py — две ЛЕГО-пальмы для главного острова (Blender, bpy).
#
# Как запустить: Blender → Scripting → вставить файл → Run Script (Alt+P)
# Или из консоли:  blender -b --factory-startup -P palms.py
#
# Стиль LEGO: ствол из состыкованных сегментов с "юбочками", блочные зубчатые
# листья, кокосы, зелёная площадка 4x4 с настоящими шипами.
# ДВЕ РАЗНОВИДНОСТИ, смотрят в РАЗНЫЕ стороны:
#   PalmA — ниже, наклон на +X (восток), 7 листьев
#   PalmB — выше, наклон на -X/-Y (юго-запад), 8 листьев, крона довёрнута
#
# Единицы: 1 юнит = 1 лего-шип (stud). Протестировано на Blender 4.x.

import bpy
import os
import math
from math import radians
from mathutils import Vector, Euler

# ----------------------------------------------------------------------------
# Очистка сцены
# ----------------------------------------------------------------------------
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

# ----------------------------------------------------------------------------
# Материалы
# ----------------------------------------------------------------------------

def make_mat(name, color, rough=0.55, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    return m


MAT_TRUNK   = make_mat("Trunk", (0.46, 0.30, 0.15), rough=0.7)
MAT_TRUNK_D = make_mat("TrunkDark", (0.36, 0.23, 0.11), rough=0.7)
MAT_LEAF_A  = make_mat("LeafA", (0.12, 0.44, 0.15))
MAT_LEAF_B  = make_mat("LeafB", (0.09, 0.38, 0.20))
MAT_PLATE   = make_mat("Plate", (0.15, 0.50, 0.13))
MAT_COCO    = make_mat("Coconut", (0.29, 0.19, 0.10), rough=0.85)
MAT_GROUND  = make_mat("Ground", (0.75, 0.64, 0.38), rough=1.0)

# ----------------------------------------------------------------------------
# Помощники
# ----------------------------------------------------------------------------

def box(name, size, loc, mat, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=2, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    if rot:
        o.rotation_euler = rot
    o.data.materials.append(mat)
    return o


def cyl(name, r, depth, loc, mat, verts=14, rot=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=verts)
    o = bpy.context.object
    o.name = name
    if rot:
        o.rotation_euler = rot
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def sphere(name, r, loc, mat, squash=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=12, ring_count=7)
    o = bpy.context.object
    o.name = name
    o.scale = (1, 1, squash)
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o

# ----------------------------------------------------------------------------
# Конструктор пальмы
# ----------------------------------------------------------------------------

def build_palm(prefix, origin, lean_dir, lean_step, segments, fronds, crown_yaw_deg, leaf_mat, seg_h=1.5):
    """ЛЕГО-пальма. lean_dir — направление наклона (нормализованный XY-вектор),
    lean_step — смещение каждого следующего сегмента ствола (в шипах)."""
    ox, oy = origin

    # Площадка 4x4 с шипами
    box(prefix + "Plate", (4, 4, 0.45), (ox, oy, 0.225), MAT_PLATE)
    for ix in range(4):
        for iy in range(4):
            cyl(prefix + "Stud_%d_%d" % (ix, iy), 0.30, 0.20,
                (ox - 1.5 + ix, oy - 1.5 + iy, 0.55), MAT_PLATE, verts=10)

    # Ствол: сегменты с "юбочками", каждый следующий смещён по lean_dir
    x, y, z = ox, oy, 0.45
    top = Vector((x, y, z))
    for i in range(segments):
        r = 0.78 - i * 0.045
        cyl(prefix + "Seg_%d" % i, r, seg_h, (x, y, z + seg_h / 2), MAT_TRUNK, verts=12)
        cyl(prefix + "Skirt_%d" % i, r + 0.22, 0.34, (x, y, z + seg_h - 0.17), MAT_TRUNK_D, verts=12)
        z += seg_h
        x += lean_dir[0] * lean_step
        y += lean_dir[1] * lean_step
        top = Vector((x, y, z))

    crown = top + Vector((0, 0, 0.1))

    # Кокосы под кроной
    for k in range(3):
        a = radians(k * 120 + 40)
        sphere(prefix + "Coco_%d" % k, 0.45,
               (crown.x + 0.85 * math.cos(a), crown.y + 0.85 * math.sin(a), crown.z - 0.15),
               MAT_COCO)

    # Листья: блочные, зубчатые (3 сужающихся слэба + кончик), поникшие вниз
    for i in range(fronds):
        yaw = radians(360.0 / fronds * i + crown_yaw_deg)
        droop = radians(24 + (i % 3) * 7)
        rot = Euler((0, droop, yaw), 'XYZ')
        segs = ((1.15, (2.2, 1.35, 0.22)), (3.15, (1.8, 1.05, 0.20)), (4.75, (1.4, 0.75, 0.18)), (5.95, (0.9, 0.42, 0.16)))
        for si, (dx, size) in enumerate(segs):
            local = Vector((dx, 0, 0.0))
            world = crown + rot.to_matrix() @ local
            box(prefix + "Frond_%d_%d" % (i, si), size, world, leaf_mat, rot=(0, droop, yaw))
        # тёмный черешок
        rib = crown + rot.to_matrix() @ Vector((1.4, 0, 0.14))
        box(prefix + "Rib_%d" % i, (2.8, 0.18, 0.10), rib, MAT_TRUNK_D, rot=(0, droop, yaw))

    # Верхушка: зелёная почка + лего-шип
    sphere(prefix + "Bud", 0.55, (crown.x, crown.y, crown.z + 0.25), leaf_mat, squash=0.8)
    cyl(prefix + "TopStud", 0.30, 0.22, (crown.x, crown.y, crown.z + 0.75), leaf_mat, verts=10)

    print("%s: высота %.1f шипов, наклон (%.2f, %.2f)" % (prefix, crown.z, lean_dir[0], lean_dir[1]))


# PalmA: наклон на ВОСТОК (+X), пониже, 7 листьев
build_palm("PA_", (-5.5, 0), (1.0, 0.12), 0.55, 5, 7, 0.0, MAT_LEAF_A)
# PalmB: наклон на ЮГО-ЗАПАД (-X, -Y), повыше, 8 листьев, крона довёрнута на 22°
build_palm("PB_", (5.5, 0), (-0.82, -0.57), 0.48, 6, 8, 22.0, MAT_LEAF_B)

# Земля для превью (в игру не едет)
box("Ground", (26, 20, 0.2), (0, 0, -0.1), MAT_GROUND)

# ----------------------------------------------------------------------------
# Камера, солнце, мир
# ----------------------------------------------------------------------------
bpy.ops.object.camera_add(location=(13.5, -17.5, 9.5))
cam = bpy.context.object
cam.rotation_euler = (Vector((0, 0.5, 4.6)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 36
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(0, 0, 16))
sun = bpy.context.object
sun.rotation_euler = (radians(48), 0, radians(22))
sun.data.energy = 3.4
sun.data.angle = radians(4)

world = bpy.data.worlds.new("PalmWorld")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.50, 0.66, 0.80, 1.0)

scene = bpy.context.scene
scene.render.resolution_x = 1000
scene.render.resolution_y = 760
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
# Standard вместо AgX: сочные игрушечные цвета (AgX сильно их вымывает)
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'

print("PALMS built")
