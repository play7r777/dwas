# sub_island.py — ПОД-ОСТРОВ для домов (Blender, bpy), тот же лего-стиль,
# что и главный остров: зелёная стад-плита, рваная песочная кайма, ступенчатый
# обрыв в воду. На таких площадках появляются дома (мостик строит игра).
#
# Как запустить: Blender → Scripting → вставить файл → Run Script (Alt+P)
# Или из консоли:  blender -b --factory-startup -P sub_island.py
# Экспорт: ISLAND=sub blender -b --factory-startup -P export_obj.py
#
# Единицы: 1 юнит = 1 стад. Blender 4.x.

import bpy
import os
import math
import random
import numpy as np
from math import radians
from mathutils import Vector

random.seed(77)

try:
    HERE = os.path.dirname(os.path.abspath(__file__))
except NameError:
    HERE = os.getcwd()

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

# --- те же тайлы, что у главного острова (генерируются идентично) ---

def save_img(path, arr):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    img.colorspace_settings.name = 'sRGB'
    img.pixels.foreach_set(arr[::-1].reshape(-1))
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    return path


def stud_tile(path, rgb, n=4, cell=64):
    px = n * cell
    base = np.array(rgb, dtype=np.float32) / 255.0
    yy, xx = np.meshgrid(np.arange(px), np.arange(px), indexing='ij')
    fx = (xx % cell) / cell - 0.5
    fy = (yy % cell) / cell - 0.5
    d = np.sqrt(fx * fx + fy * fy)

    def mask(dist, r, feather=0.025):
        return np.clip((r - dist) / feather, 0, 1)

    col = np.tile(base, (px, px, 1))
    face = mask(d, 0.295)
    ring = mask(d, 0.345) * (1 - mask(d, 0.300))
    col = col * (1 + 0.10 * face[..., None])
    col = col * (1 - 0.17 * ring[..., None])
    d2 = np.sqrt((fx + 0.09) ** 2 + (fy - 0.09) ** 2)
    glint = mask(d2, 0.115) * face
    col = col + 0.13 * glint[..., None]
    out = np.zeros((px, px, 4), dtype=np.float32)
    out[..., :3] = np.clip(col, 0, 1)
    out[..., 3] = 1.0
    return save_img(path, out)


def flat_tile(path, rgb):
    out = np.zeros((16, 16, 4), dtype=np.float32)
    out[..., :3] = np.array(rgb, dtype=np.float32) / 255.0
    out[..., 3] = 1.0
    return save_img(path, out)


TILES = {
    "grass": stud_tile(os.path.join(HERE, "tile_grass.png"), (86, 165, 54)),
    "sand": stud_tile(os.path.join(HERE, "tile_sand.png"), (238, 192, 104)),
    "sand2": stud_tile(os.path.join(HERE, "tile_sand2.png"), (226, 176, 88)),
    "f_green": flat_tile(os.path.join(HERE, "tile_f_green.png"), (58, 122, 38)),
    "f_sand": flat_tile(os.path.join(HERE, "tile_f_sand.png"), (216, 166, 82)),
    "f_cliff": flat_tile(os.path.join(HERE, "tile_f_cliff.png"), (196, 148, 70)),
    "f_rock": flat_tile(os.path.join(HERE, "tile_f_rock.png"), (88, 90, 94)),
}

_mats = {}

def tex_mat(key, rough=0.6):
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("M_" + key)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(TILES[key])
    tex.interpolation = 'Closest' if key.startswith("f_") else 'Linear'
    m.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    _mats[key] = m
    return m


def plate(name, size, loc, top_key, side_key, uv_div=4.0):
    bpy.ops.mesh.primitive_cube_add(size=2, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = o.data
    me.materials.append(tex_mat(top_key))
    me.materials.append(tex_mat(side_key))
    # ВАЖНО: пишем в существующий активный UV-слой куба (см. main_island.py)
    uv = me.uv_layers[0] if len(me.uv_layers) else me.uv_layers.new(name="UVMap")
    me.uv_layers.active = uv
    for poly in me.polygons:
        top = poly.normal.z > 0.5
        poly.material_index = 0 if top else 1
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (v.x / uv_div, v.y / uv_div) if top else (0.5, 0.5)
    return o


def flat_box(name, size, loc, key):
    bpy.ops.mesh.primitive_cube_add(size=2, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = o.data
    me.materials.append(tex_mat(key))
    uv = me.uv_layers[0] if len(me.uv_layers) else me.uv_layers.new(name="UVMap")
    me.uv_layers.active = uv
    for poly in me.polygons:
        for li in poly.loop_indices:
            uv.data[li].uv = (0.5, 0.5)
    return o

# ----------------------------------------------------------------------------
# Геометрия под-острова (верх газона на z=0, сторона ~56)
# ----------------------------------------------------------------------------
S = 44.0
SH = S / 2

plate("GreenTop", (S, S, 1.2), (0, 0, -0.6), "grass", "f_green")

# Сплошной песочный "фартук" под каймой (закрывает просветы между плитами)
AP = 14
flat_box("ApronN", (S + 2 * AP - 6, AP, 1.0), (0, SH + AP / 2 - 4, -1.2), "f_sand")
flat_box("ApronS", (S + 2 * AP - 6, AP, 1.0), (0, -(SH + AP / 2 - 4), -1.2), "f_sand")
flat_box("ApronE", (AP, S + 2, 1.0), (SH + AP / 2 - 4, 0, -1.2), "f_sand")
flat_box("ApronW", (AP, S + 2, 1.0), (-(SH + AP / 2 - 4), 0, -1.2), "f_sand")

# Песочная кайма из перекрывающихся плит
idx = 0
step = 12
for side in range(4):
    n = int((S + 14) // step) + 1
    for i in range(n):
        along = -SH - 7 + 5 + i * step + random.uniform(-2, 2)
        w = random.uniform(8, 12)
        off = SH + w / 2 - 3.5
        if side == 0:
            c, s = (along, off), (step * 1.35, w)
        elif side == 1:
            c, s = (along, -off), (step * 1.35, w)
        elif side == 2:
            c, s = (off, along), (w, step * 1.35)
        else:
            c, s = (-off, along), (w, step * 1.35)
        key = "sand" if idx % 2 == 0 else "sand2"
        # Джиттер высоты против копланарных наложений (см. main_island.py)
        jit = random.uniform(0, 0.22)
        plate("Sand_%d_%d" % (side, i), (s[0], s[1], 1.2), (c[0], c[1], -0.95 - jit), key, "f_sand")
        idx += 1

# Ступенчатый обрыв + камень
flat_box("Cliff1", (S + 22, S + 22, 5), (0, 0, -1.55 - 2.5), "f_sand")
flat_box("Cliff2", (S + 2, S + 2, 5), (0, 0, -6.55 - 2.5), "f_cliff")
flat_box("Rock", (S - 12, S - 12, 4), (0, 0, -11.55 - 2.0), "f_rock")

# ----------------------------------------------------------------------------
# Камера, солнце, мир
# ----------------------------------------------------------------------------
bpy.ops.object.camera_add(location=(38, -62, 42))
cam = bpy.context.object
cam.rotation_euler = (Vector((0, 0, -4)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 38
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(0, 0, 40))
sun = bpy.context.object
sun.rotation_euler = (radians(44), 0, radians(24))
sun.data.energy = 3.0
sun.data.angle = radians(3)

world = bpy.data.worlds.new("SubIslandWorld")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.36, 0.62, 0.86, 1.0)

scene = bpy.context.scene
scene.render.resolution_x = 1000
scene.render.resolution_y = 780
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'

print("SUB ISLAND built")
