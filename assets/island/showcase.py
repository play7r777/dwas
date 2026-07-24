# showcase.py — сборочный рендер: главный лего-остров + пальмы + ПВО + кафе +
# ракеты в зоне, всё из ГОТОВЫХ экспортированных OBJ (проверка, что ассеты
# собираются вместе как в игре).
#
# Запуск: blender -b --factory-startup -P showcase.py
import bpy
import os
from math import radians
from mathutils import Vector

try:
    HERE = os.path.dirname(os.path.abspath(__file__))
except NameError:
    HERE = os.getcwd()
ASSETS = os.path.dirname(HERE)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)


def imp(path, loc=(0, 0, 0), rot_z=0.0, scale=1.0, rot_x=0.0):
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        o.location = Vector(o.location) * scale + Vector(loc)
        o.rotation_euler = (o.rotation_euler[0] + rot_x, o.rotation_euler[1], o.rotation_euler[2] + rot_z)
        o.scale = (o.scale[0] * scale, o.scale[1] * scale, o.scale[2] * scale)
    return new


# Остров (как есть: зона ракет справа, газон слева). Экспортный OBJ имеет НИЗ
# на z=0 — верх (зелёная плита) вычисляем по bbox и ставим декор на него.
island_objs = imp(os.path.join(HERE, "main_island.obj"))
bpy.context.view_layer.update()
TOP = max((o.matrix_world @ Vector(c)).z for o in island_objs for c in o.bound_box)
print("ISLAND TOP =", TOP)

# Ракеты в зоне: чем дальше — тем больше (Mk1 -> Mk4)
for mk, y in ((1, -46), (2, -16), (3, 15), (4, 48)):
    imp(os.path.join(ASSETS, "rockets", "rocket_mk%d.obj" % mk), loc=(41.5, y, TOP + 0.3))

# Две пальмы на газоне (смотрят в разные стороны)
imp(os.path.join(ASSETS, "palm_trees", "palm_a.obj"), loc=(-55, 52, TOP + 0.2))
imp(os.path.join(ASSETS, "palm_trees", "palm_b.obj"), loc=(-12, 54, TOP + 0.2), rot_z=radians(140))

# ПВО на газоне: base (низ на z=0), head (пивот 8.1), barrels (пивот стволов)
PX, PY = -34, 18
imp(os.path.join(ASSETS, "air_defense", "air_defense_base.obj"), loc=(PX, PY, TOP + 0.3))
imp(os.path.join(ASSETS, "air_defense", "air_defense_head.obj"), loc=(PX, PY, TOP + 8.4), rot_z=radians(-30))
# блок стволов: смещён на 4.6 юнита вперёд от пивота башни
# (вперёд = -Y детали, довёрнутой на -30° вокруг Z)
import math
fx = math.sin(radians(-30)) * 4.6        # x-компонента поворота вектора (0,-4.6)
fy = -math.cos(radians(-30)) * 4.6       # y-компонента
imp(os.path.join(ASSETS, "air_defense", "air_defense_barrels.obj"),
    loc=(PX + fx, PY + fy, TOP + 8.4), rot_z=radians(-30), rot_x=radians(8))

# Кафе (уровень 5, новенькое) на газоне, фасадом на юг; масштаб как в игре:
# ширина кафе 7.4 юнита -> 26 стадов
imp(os.path.join(ASSETS, "cafe", "cafe_lvl5.obj"), loc=(-35, -32, TOP + 0.2), scale=26 / 7.4)

# Камера/свет/мир
bpy.ops.object.camera_add(location=(60, -210, 175))
cam = bpy.context.object
cam.rotation_euler = (Vector((0, -8, TOP)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 40
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(0, 0, 80))
sun = bpy.context.object
sun.rotation_euler = (radians(42), 0, radians(24))
sun.data.energy = 3.0
sun.data.angle = radians(3)

world = bpy.data.worlds.new("ShowcaseWorld")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.36, 0.62, 0.86, 1.0)

scene = bpy.context.scene
scene.render.resolution_x = 1300
scene.render.resolution_y = 950
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 40
scene.cycles.use_denoising = True
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'
scene.render.filepath = os.path.join(HERE, "preview_showcase.png")
bpy.ops.render.render(write_still=True)
print("SHOWCASE DONE")
