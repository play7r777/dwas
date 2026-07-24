# rockets.py — ЛЕГО-ракеты Mk I..IV для зоны запуска главного острова (Blender, bpy).
#
# Как запустить: Blender → Scripting → вставить файл → Run Script (Alt+P)
# Или из консоли:  blender -b --factory-startup -P rockets.py
#
# ЧЕТЫРЕ разновидности под 4 стенда острова: чем дальше стенд — тем КРУПНЕЕ
# ракета (начинаем с маленькой) и свой цвет:
#   Mk1 — красная, 10 шипов   Mk2 — оранжевая, 14 шипов
#   Mk3 — бирюзовая, 19 шипов Mk4 — фиолетовая, 25 шипов
# Игрушечный стиль: цветной корпус, белая полоса и белый нос, серые сопла,
# лего-шип на самом кончике. Единицы: 1 юнит = 1 стад. Blender 4.x.

import bpy
import os
import math
from math import radians
from mathutils import Vector

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def make_mat(name, color, rough=0.45, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    return m


MAT_WHITE  = make_mat("White", (0.92, 0.92, 0.90))
MAT_DARK   = make_mat("DarkMetal", (0.15, 0.16, 0.17), rough=0.5, metallic=0.5)
MAT_GRAY   = make_mat("Gray", (0.52, 0.54, 0.56), rough=0.5, metallic=0.3)
MAT_GLASS  = make_mat("Porthole", (0.55, 0.78, 0.85), rough=0.15)
MAT_GROUND = make_mat("Ground", (0.58, 0.58, 0.56), rough=1.0)

ROCKETS = {
    1: {"h": 10.0, "r": 1.50, "fins": 3, "color": (0.80, 0.10, 0.10)},   # красная
    2: {"h": 14.0, "r": 1.95, "fins": 3, "color": (0.92, 0.46, 0.04)},   # оранжевая
    3: {"h": 19.0, "r": 2.50, "fins": 4, "color": (0.03, 0.55, 0.58)},   # бирюзовая
    4: {"h": 25.0, "r": 3.20, "fins": 4, "color": (0.44, 0.12, 0.64)},   # фиолетовая
}


def cyl(name, r, depth, loc, mat, verts=22, rot=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=verts)
    o = bpy.context.object
    o.name = name
    if rot:
        o.rotation_euler = rot
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def cone(name, r1, r2, depth, loc, mat, verts=22):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth, location=loc, vertices=verts)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return o


def box(name, size, loc, mat, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=2, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    if rot:
        o.rotation_euler = rot
    o.data.materials.append(mat)
    return o


def prism(name, pts_xz, thickness, loc, mat, yaw=0.0):
    """Призма из 2D-контура (XZ), выдавленная по Y — для плавников."""
    n = len(pts_xz)
    verts = [(x, -thickness / 2, z) for x, z in pts_xz] + [(x, thickness / 2, z) for x, z in pts_xz]
    faces = [list(range(n - 1, -1, -1)), [i + n for i in range(n)]]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, j + n, i + n])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.validate()
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    o.location = loc
    o.rotation_euler = (0, 0, yaw)
    o.data.materials.append(mat)
    return o


def build_rocket(mark, cx):
    cfg = ROCKETS[mark]
    h, r = cfg["h"], cfg["r"]
    p = "R%d_" % mark
    body_mat = make_mat("Body_%d" % mark, cfg["color"])
    fin_mat = make_mat("Fin_%d" % mark, tuple(c * 0.55 for c in cfg["color"]))

    z_skirt = h * 0.14
    z_body_top = h * 0.62
    z_taper_top = h * 0.70

    # Сопло и юбка двигателя
    cyl(p + "Nozzle", r * 0.55, z_skirt * 0.9, (cx, 0, z_skirt * 0.30), MAT_DARK, verts=16)
    cone(p + "Skirt", r * 1.08, r * 0.88, z_skirt, (cx, 0, z_skirt / 2 + 0.3), MAT_GRAY)

    # Корпус
    body_h = z_body_top - z_skirt
    cyl(p + "Body", r, body_h, (cx, 0, z_skirt + body_h / 2), body_mat)

    # Белая полоса посередине и тонкое кольцо ниже
    cyl(p + "Band", r + 0.07, h * 0.075, (cx, 0, h * 0.46), MAT_WHITE)
    cyl(p + "Ring", r + 0.05, h * 0.022, (cx, 0, h * 0.28), MAT_WHITE)

    # Переход и белый нос с цветным кончиком
    cone(p + "Taper", r, r * 0.68, z_taper_top - z_body_top, (cx, 0, (z_body_top + z_taper_top) / 2), body_mat)
    nose_h = h - z_taper_top - 0.45
    cone(p + "Nose", r * 0.68, 0.16, nose_h, (cx, 0, z_taper_top + nose_h / 2), MAT_WHITE)
    cyl(p + "TipStud", 0.30, 0.35, (cx, 0, h - 0.25), body_mat, verts=10)

    # Иллюминатор (со 2-й марки)
    if mark >= 2:
        cyl(p + "PortRim", r * 0.34, 0.24, (cx, -r + 0.02, h * 0.52), MAT_GRAY,
            rot=(radians(90), 0, 0), verts=16)
        cyl(p + "PortGlass", r * 0.24, 0.26, (cx, -r + 0.00, h * 0.52), MAT_GLASS,
            rot=(radians(90), 0, 0), verts=16)

    # Плавники
    fin_h = h * 0.24
    fin_w = r * 1.35
    for i in range(cfg["fins"]):
        yaw = radians(360.0 / cfg["fins"] * i + (0 if cfg["fins"] == 4 else 90))
        pts = [(r * 0.55, 0.2), (r * 0.55 + fin_w, 0.0), (r * 0.55 + fin_w * 0.72, fin_h * 0.42), (r * 0.55, fin_h)]
        prism(p + "Fin_%d" % i, pts, 0.32, (cx, 0, 0.2), fin_mat, yaw=yaw)

    # У Mk4 — дополнительное кольцо и антенна (флагман)
    if mark == 4:
        cyl(p + "Band2", r + 0.07, h * 0.05, (cx, 0, h * 0.36), MAT_WHITE)
        cyl(p + "Antenna", 0.08, 2.2, (cx + r * 0.5, 0, z_taper_top + 1.0), MAT_GRAY, verts=8)

    print("Mk%d built: h=%.1f r=%.1f at x=%.1f" % (mark, h, r, cx))


# Ряд: от маленькой к большой (как в зоне на острове)
build_rocket(1, -13.0)
build_rocket(2, -4.5)
build_rocket(3, 5.0)
build_rocket(4, 16.0)

# Площадка для превью (в игру не едет)
box("Ground", (44, 26, 0.3), (1.5, 0, -0.15), MAT_GROUND)

# Камера/свет
bpy.ops.object.camera_add(location=(6, -56, 22))
cam = bpy.context.object
cam.rotation_euler = (Vector((1.5, 0, 10)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 36
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(0, 0, 30))
sun = bpy.context.object
sun.rotation_euler = (radians(52), 0, radians(18))
sun.data.energy = 3.2
sun.data.angle = radians(4)

world = bpy.data.worlds.new("RocketWorld")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.52, 0.66, 0.80, 1.0)

scene = bpy.context.scene
scene.render.resolution_x = 1100
scene.render.resolution_y = 700
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
# Standard вместо AgX: сочные игрушечные цвета (AgX сильно их вымывает)
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'

print("ROCKETS built")
