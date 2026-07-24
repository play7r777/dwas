# bullet.py — трассерная ПУЛЯ для ПВО-минигана (Blender headless, bpy).
#
# Стилизованный трассер: остроконечная оживальная головка, гильзо-цилиндр,
# ведущий поясок у основания. Один плоский материал (цвет зашит в MTL, Kd) —
# без текстур, как у деталей острова: в игре пуля перекрашивается кодом
# (Neon, жёлто-оранжевый) и летит из дула турели (AirDefenseManager).
#
# Ориентация: нос вдоль Blender +Z → после экспорта OBJ (Y-up) нос по +Y,
# как у ракет rocket_mkN. Игра доворачивает нос по полёту сама.
#
# Запуск:  blender -b --factory-startup -P bullet.py
#          PREVIEW=1 blender -b --factory-startup -P bullet.py  (+ рендер)
# Выход:   bullet.obj + bullet.mtl (+ preview_bullet.png)
import bpy
import os
from math import radians

HERE = os.path.dirname(os.path.abspath(__file__))
EXPORT_DIR = os.environ.get("EXPORT_DIR", HERE)
os.makedirs(EXPORT_DIR, exist_ok=True)

# --- Чистая сцена ---
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# --- Материал: латунно-огненный трассер (цвет уедет в Kd при экспорте) ---
mat = bpy.data.materials.new("M_tracer")
mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1.0, 0.72, 0.20, 1.0)
mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.35

def add(obj):
    obj.data.materials.append(mat)
    return obj

# --- Геометрия (длина ~1.0, диаметр 0.28; 16-гранник — дёшево и кругло) ---
SEGS = 16

# Тело-гильза: z 0.00..0.55
bpy.ops.mesh.primitive_cylinder_add(vertices=SEGS, radius=0.14, depth=0.55, location=(0, 0, 0.275))
add(bpy.context.object).name = "Body"

# Ведущий поясок у основания (чуть шире тела): z 0.06..0.15
bpy.ops.mesh.primitive_cylinder_add(vertices=SEGS, radius=0.158, depth=0.09, location=(0, 0, 0.105))
add(bpy.context.object).name = "Band"

# Оживальная головка: усечённый конус со скруглённым кончиком, z 0.55..0.97
bpy.ops.mesh.primitive_cone_add(vertices=SEGS, radius1=0.14, radius2=0.030, depth=0.42, location=(0, 0, 0.76))
add(bpy.context.object).name = "Nose"

# Светящийся кончик трассера: маленькая сфера на носу
bpy.ops.mesh.primitive_uv_sphere_add(segments=SEGS, ring_count=8, radius=0.045, location=(0, 0, 0.975))
add(bpy.context.object).name = "Tip"

# --- Джойним в один меш, низ на z=0, центр по XY в origin ---
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
bullet = bpy.context.object
bullet.name = "bullet"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

tris = sum(len(p.vertices) - 2 for p in bullet.data.polygons)
print("BULLET tris = %d" % tris)

# --- (опция) превью для проверки глазами ---
if os.environ.get("PREVIEW", "0") == "1":
    bpy.ops.object.camera_add(location=(1.6, -2.2, 1.35))
    cam = bpy.context.object
    from mathutils import Vector
    cam.rotation_euler = (Vector((0, 0, 0.5)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
    cam.data.lens = 50
    scene.camera = cam

    bpy.ops.object.light_add(type='SUN', location=(0, 0, 6))
    sun = bpy.context.object
    sun.rotation_euler = (radians(35), 0, radians(40))
    sun.data.energy = 4.0

    world = bpy.data.worlds.new("W")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.18, 0.22, 0.28, 1.0)

    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 560
    scene.render.resolution_y = 560
    scene.view_settings.view_transform = 'Standard'
    scene.render.filepath = os.path.join(EXPORT_DIR, "preview_bullet.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW:", scene.render.filepath)

# --- Экспорт OBJ + MTL (цвет в Kd — цветное превью в Import 3D) ---
obj_path = os.path.join(EXPORT_DIR, "bullet.obj")
bpy.ops.object.select_all(action='DESELECT')
bullet.select_set(True)
bpy.context.view_layer.objects.active = bullet
bpy.ops.wm.obj_export(
    filepath=obj_path,
    export_selected_objects=True,
    export_materials=True,
    path_mode='COPY',
)
print("EXPORTED:", obj_path)
print("BULLET DONE")
