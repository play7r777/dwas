# main_island.py — ГЛАВНЫЙ ЛЕГО-ОСТРОВ по референс-скриншоту (Blender, bpy).
#
# Как запустить: Blender → Scripting → вставить файл → Run Script (Alt+P)
# Или из консоли:  blender -b --factory-startup -P main_island.py
#
# Планировка (вид сверху, как на скрине):
#   • рваная песочная кайма из лего-плит + ступенчатый обрыв в воду
#   • зелёная стад-плита 204x204
#   • кольцевая дорога с жёлтым пунктиром и светлыми тротуарами-бордюрами
#   • вертикальная дорога-перемычка делит центр
#   • СЛЕВА — газон, СПРАВА — бетонная площадка, обведённая ЧЁРНО-ЖЁЛТОЙ
#     сигнальной лентой: зона ракет (в превью стоят 4 лего-ракеты Mk1..Mk4,
#     чем дальше — тем крупнее; в экспорт острова они не попадают)
#
# Шипы (studs) на площадках — ТАЙЛОВЫЕ ТЕКСТУРЫ (tile_*.png генерируются тут же
# через numpy): геометрия остаётся в лимитах Roblox, а грид шипов остаётся
# чётким при любом масштабе. Единицы: 1 юнит = 1 стад. Blender 4.x.

import bpy
import os
import math
import random
import numpy as np
from math import radians
from mathutils import Vector

random.seed(325)

try:
    HERE = os.path.dirname(os.path.abspath(__file__))
except NameError:
    HERE = os.getcwd()

# ----------------------------------------------------------------------------
# Очистка сцены
# ----------------------------------------------------------------------------
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

# ----------------------------------------------------------------------------
# ТАЙЛОВЫЕ ТЕКСТУРЫ ШИПОВ (4x4 шипа на тайл, 64px на шип) + плоские цвета
# ----------------------------------------------------------------------------

def save_img(path, arr):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    img.colorspace_settings.name = 'sRGB'
    flat = arr[::-1].reshape(-1)
    img.pixels.foreach_set(flat)
    img.filepath_raw = path
    img.file_format = 'PNG'
    img.save()
    return path


def stud_tile(path, rgb, n=4, cell=64):
    """Тайл лего-шипов: круглый шип, светлый верх, тёмное кольцо, блик."""
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
    "grass":    stud_tile(os.path.join(HERE, "tile_grass.png"),    (86, 165, 54)),
    "sidewalk": stud_tile(os.path.join(HERE, "tile_sidewalk.png"), (206, 208, 204)),
    "asphalt":  stud_tile(os.path.join(HERE, "tile_asphalt.png"),  (62, 64, 68)),
    "concrete": stud_tile(os.path.join(HERE, "tile_concrete.png"), (148, 150, 149)),
    "sand":     stud_tile(os.path.join(HERE, "tile_sand.png"),     (238, 192, 104)),
    "sand2":    stud_tile(os.path.join(HERE, "tile_sand2.png"),    (226, 176, 88)),
    "f_green":   flat_tile(os.path.join(HERE, "tile_f_green.png"),   (58, 122, 38)),
    "f_sand":    flat_tile(os.path.join(HERE, "tile_f_sand.png"),    (216, 166, 82)),
    "f_cliff":   flat_tile(os.path.join(HERE, "tile_f_cliff.png"),   (196, 148, 70)),
    "f_rock":    flat_tile(os.path.join(HERE, "tile_f_rock.png"),    (88, 90, 94)),
    "f_gray":    flat_tile(os.path.join(HERE, "tile_f_gray.png"),    (168, 170, 168)),
    "f_asphalt": flat_tile(os.path.join(HERE, "tile_f_asphalt.png"), (48, 50, 54)),
    "f_black":   flat_tile(os.path.join(HERE, "tile_f_black.png"),   (26, 27, 29)),
    "f_yellow":  flat_tile(os.path.join(HERE, "tile_f_yellow.png"),  (247, 200, 20)),
}

# ----------------------------------------------------------------------------
# Материалы
# ----------------------------------------------------------------------------
_mats = {}

def tex_mat(key, rough=0.6):
    if key in _mats:
        return _mats[key]
    m = bpy.data.materials.new("M_" + key)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    links = m.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(TILES[key])
    tex.interpolation = 'Closest' if key.startswith("f_") else 'Linear'
    links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    _mats[key] = m
    return m


def simple_mat(name, color, rough=0.6):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    return m

# ----------------------------------------------------------------------------
# Помощники геометрии
# ----------------------------------------------------------------------------
ISLAND_PARTS = []   # что уедет в экспорт
PREVIEW_PARTS = []  # только для превью (ракеты)


def plate(name, size, loc, top_key, side_key, uv_div=4.0, preview=False):
    """Плита: верхняя грань — тайловая стад-текстура (UV по мировым XY),
    боковые/нижняя — плоский цветовой тайл."""
    bpy.ops.mesh.primitive_cube_add(size=2, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = o.data
    me.materials.append(tex_mat(top_key))
    me.materials.append(tex_mat(side_key))
    # ВАЖНО: пишем в СУЩЕСТВУЮЩИЙ активный UV-слой куба (uv_layers.new создал бы
    # второй слой, а рендер/экспорт продолжили бы читать первый).
    uv = me.uv_layers[0] if len(me.uv_layers) else me.uv_layers.new(name="UVMap")
    me.uv_layers.active = uv
    for poly in me.polygons:
        top = poly.normal.z > 0.5
        poly.material_index = 0 if top else 1
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            if top:
                uv.data[li].uv = (v.x / uv_div, v.y / uv_div)
            else:
                uv.data[li].uv = (0.5, 0.5)
    (PREVIEW_PARTS if preview else ISLAND_PARTS).append(o)
    return o


def flat_box(name, size, loc, key, preview=False):
    """Бокс одним плоским цветом (через крошечный тайл — Roblox уважает map_Kd)."""
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
    (PREVIEW_PARTS if preview else ISLAND_PARTS).append(o)
    return o

# ----------------------------------------------------------------------------
# ГЕОМЕТРИЯ ОСТРОВА (зелёный верх на z=0)
# ----------------------------------------------------------------------------
G = 204.0   # сторона зелёной плиты
GH = G / 2

# Зелёная база
plate("GreenBase", (G, G, 1.2), (0, 0, -0.6), "grass", "f_green")

# Сплошной песочный "фартук" ПОД рваной каймой: закрывает любые просветы между
# случайными плитами (иначе в щелях чернота).
APRON_W = 30
flat_box("ApronN", (G + 2 * APRON_W - 8, APRON_W, 1.0), (0, GH + APRON_W / 2 - 6, -1.2), "f_sand")
flat_box("ApronS", (G + 2 * APRON_W - 8, APRON_W, 1.0), (0, -(GH + APRON_W / 2 - 6), -1.2), "f_sand")
flat_box("ApronE", (APRON_W, G + 4, 1.0), (GH + APRON_W / 2 - 6, 0, -1.2), "f_sand")
flat_box("ApronW", (APRON_W, G + 4, 1.0), (-(GH + APRON_W / 2 - 6), 0, -1.2), "f_sand")

# Рваная песочная кайма: перекрывающиеся плиты двух оттенков, верх чуть ниже газона
def sand_ring(top_z, inset, w_lo, w_hi, key_a, key_b):
    step = 22
    idx = 0
    for side in range(4):
        n = int((G + 24) // step) + 1
        for i in range(n):
            along = -GH - 12 + 8 + i * step + random.uniform(-3, 3)
            w = random.uniform(w_lo, w_hi)
            off = GH + w / 2 - inset
            if side == 0:
                c, s = (along, off), (step * 1.35, w)
            elif side == 1:
                c, s = (along, -off), (step * 1.35, w)
            elif side == 2:
                c, s = (off, along), (w, step * 1.35)
            else:
                c, s = (-off, along), (w, step * 1.35)
            key = key_a if (idx % 2 == 0) else key_b
            # Джиттер высоты: перекрывающиеся плиты НЕ копланарны (иначе чёрные
            # артефакты в Cycles и z-fighting в Roblox), а кайма выглядит как
            # настоящие лего-плиты разной толщины.
            jit = random.uniform(0, 0.22)
            plate("Sand_%d_%d" % (side, i), (s[0], s[1], 1.2), (c[0], c[1], top_z - jit - 0.6), key, "f_sand")
            idx += 1

sand_ring(-0.35, 6.0, 14, 20, "sand", "sand2")   # верхний ряд, заходит под газон
sand_ring(-0.95, -2.0, 10, 16, "sand2", "sand")  # нижний ряд, торчит наружу

# Ступенчатый обрыв в воду + тёмное каменное дно
flat_box("Cliff1", (G + 34, G + 34, 7), (0, 0, -1.7 - 3.5), "f_sand")
flat_box("Cliff2", (G + 8, G + 8, 7), (0, 0, -8.7 - 3.5), "f_cliff")
flat_box("Cliff3", (G - 12, G - 12, 7), (0, 0, -15.7 - 3.5), "f_cliff")
flat_box("RockBottom", (G - 32, G - 32, 5), (0, 0, -22.7 - 2.5), "f_rock")

# --- Тротуары и кольцевая дорога ---
SW_OUT, ROAD_W, SW_W = 174.0, 12.0, 4.0
half_out = SW_OUT / 2                    # 87
road_out = SW_OUT - 2 * SW_W             # 166
half_road = road_out / 2                 # 83
sw_in = road_out - 2 * ROAD_W            # 142
half_in = sw_in / 2                      # 71

# внешний тротуар (рамка)
plate("SWo_N", (SW_OUT, SW_W, 0.5), (0, half_out - SW_W / 2, 0.0), "sidewalk", "f_gray")
plate("SWo_S", (SW_OUT, SW_W, 0.5), (0, -(half_out - SW_W / 2), 0.0), "sidewalk", "f_gray")
plate("SWo_E", (SW_W, SW_OUT - 2 * SW_W, 0.5), (half_out - SW_W / 2, 0, 0.0), "sidewalk", "f_gray")
plate("SWo_W", (SW_W, SW_OUT - 2 * SW_W, 0.5), (-(half_out - SW_W / 2), 0, 0.0), "sidewalk", "f_gray")

# дорога (рамка)
plate("Road_N", (road_out, ROAD_W, 0.36), (0, half_road - ROAD_W / 2, -0.07), "asphalt", "f_asphalt")
plate("Road_S", (road_out, ROAD_W, 0.36), (0, -(half_road - ROAD_W / 2), -0.07), "asphalt", "f_asphalt")
plate("Road_E", (ROAD_W, road_out - 2 * ROAD_W, 0.36), (half_road - ROAD_W / 2, 0, -0.07), "asphalt", "f_asphalt")
plate("Road_W", (ROAD_W, road_out - 2 * ROAD_W, 0.36), (-(half_road - ROAD_W / 2), 0, -0.07), "asphalt", "f_asphalt")

# внутренний тротуар (рамка)
plate("SWi_N", (sw_in, SW_W, 0.5), (0, half_in - SW_W / 2, 0.0), "sidewalk", "f_gray")
plate("SWi_S", (sw_in, SW_W, 0.5), (0, -(half_in - SW_W / 2), 0.0), "sidewalk", "f_gray")
plate("SWi_E", (SW_W, sw_in - 2 * SW_W, 0.5), (half_in - SW_W / 2, 0, 0.0), "sidewalk", "f_gray")
plate("SWi_W", (SW_W, sw_in - 2 * SW_W, 0.5), (-(half_in - SW_W / 2), 0, 0.0), "sidewalk", "f_gray")

# вертикальная дорога-перемычка (x = +6) со своими тротуарами
MID_X = 6.0
inner_len = sw_in - 2 * SW_W  # 134
plate("RoadMid", (ROAD_W, inner_len, 0.36), (MID_X, 0, -0.07), "asphalt", "f_asphalt")
plate("SWm_W", (SW_W, inner_len, 0.5), (MID_X - ROAD_W / 2 - SW_W / 2, 0, 0.0), "sidewalk", "f_gray")
plate("SWm_E", (SW_W, inner_len, 0.5), (MID_X + ROAD_W / 2 + SW_W / 2, 0, 0.0), "sidewalk", "f_gray")

# --- Газон слева ---
lawn_w = (MID_X - ROAD_W / 2 - SW_W) - (-(half_in - SW_W))  # от внутр. тротуара до перемычки
lawn_cx = (-(half_in - SW_W) + (MID_X - ROAD_W / 2 - SW_W)) / 2
plate("Lawn", (lawn_w, inner_len, 0.44), (lawn_cx, 0, 0.03), "grass", "f_green")

# --- Бетонная площадка справа (ЗОНА РАКЕТ) ---
pad_x0 = MID_X + ROAD_W / 2 + SW_W
pad_x1 = half_in - SW_W
pad_cx = (pad_x0 + pad_x1) / 2
pad_w = pad_x1 - pad_x0
plate("RocketPad", (pad_w, inner_len, 0.5), (pad_cx, 0, 0.0), "concrete", "f_gray")

# Чёрно-жёлтая сигнальная лента по периметру площадки
BAND = 3.0
hz_hw = pad_w / 2 - 2.0
hz_hh = inner_len / 2 - 2.0
flat_box("HzN", (hz_hw * 2, BAND, 0.5), (pad_cx, hz_hh - BAND / 2 + 2 - 2, 0.06), "f_black")
flat_box("HzS", (hz_hw * 2, BAND, 0.5), (pad_cx, -(hz_hh - BAND / 2), 0.06), "f_black")
flat_box("HzW", (BAND, hz_hh * 2 - 2 * BAND, 0.5), (pad_cx - hz_hw + BAND / 2, 0, 0.06), "f_black")
flat_box("HzE", (BAND, hz_hh * 2 - 2 * BAND, 0.5), (pad_cx + hz_hw - BAND / 2, 0, 0.06), "f_black")
# жёлтые сегменты (шахматка) поверх чёрной ленты
seg, gap = 4.0, 4.0
x = pad_cx - hz_hw + BAND + 1
while x + seg / 2 < pad_cx + hz_hw - BAND - 1:
    flat_box("HzYN_%d" % int(x), (seg, BAND, 0.14), (x + seg / 2, hz_hh - BAND / 2, 0.28), "f_yellow")
    flat_box("HzYS_%d" % int(x), (seg, BAND, 0.14), (x + seg / 2, -(hz_hh - BAND / 2), 0.28), "f_yellow")
    x += seg + gap
y = -hz_hh + BAND + 1
while y + seg / 2 < hz_hh - BAND - 1:
    flat_box("HzYW_%d" % int(y), (BAND, seg, 0.14), (pad_cx - hz_hw + BAND / 2, y + seg / 2, 0.28), "f_yellow")
    flat_box("HzYE_%d" % int(y), (BAND, seg, 0.14), (pad_cx + hz_hw - BAND / 2, y + seg / 2, 0.28), "f_yellow")
    y += seg + gap

# --- Жёлтый пунктир дорог ---
def dash(name, cx, cy, along_x):
    size = (3.0, 0.9, 0.12) if along_x else (0.9, 3.0, 0.12)
    flat_box(name, size, (cx, cy, 0.13), "f_yellow")

for x in range(-72, 73, 8):
    dash("DashN_%d" % x, x, half_road - ROAD_W / 2, True)
    dash("DashS_%d" % x, x, -(half_road - ROAD_W / 2), True)
for y in range(-64, 65, 8):
    dash("DashE_%d" % y, half_road - ROAD_W / 2, y, False)
    dash("DashW_%d" % y, -(half_road - ROAD_W / 2), y, False)
for y in range(-56, 57, 8):
    dash("DashM_%d" % y, MID_X, y, False)

# ----------------------------------------------------------------------------
# ПРЕВЬЮ: 4 лего-ракеты в зоне (Mk1 маленькая → Mk4 большая). В экспорт НЕ идут —
# полноценные ракеты с запечёнными текстурами лежат в assets/rockets/.
# ----------------------------------------------------------------------------
MAT_WHITE = simple_mat("PrvWhite", (0.92, 0.92, 0.90), rough=0.45)
MAT_DARKM = simple_mat("PrvDark", (0.15, 0.16, 0.17), rough=0.5)
MAT_GRAYM = simple_mat("PrvGray", (0.52, 0.54, 0.56), rough=0.5)


def prv_cyl(name, r, depth, loc, mat, verts=18):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=verts)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    PREVIEW_PARTS.append(o)
    return o


def prv_cone(name, r1, r2, depth, loc, mat, verts=18):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth, location=loc, vertices=verts)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    PREVIEW_PARTS.append(o)
    return o


def preview_rocket(mark, cx, cy):
    h = {1: 10.0, 2: 14.0, 3: 19.0, 4: 25.0}[mark]
    r = {1: 1.5, 2: 1.95, 3: 2.5, 4: 3.2}[mark]
    color = {1: (0.80, 0.10, 0.10), 2: (0.92, 0.46, 0.04), 3: (0.03, 0.55, 0.58), 4: (0.44, 0.12, 0.64)}[mark]
    mat = simple_mat("PrvBody%d" % mark, color, rough=0.45)
    z0 = 0.25
    prv_cyl("PRV_noz%d" % mark, r * 0.55, 1.0, (cx, cy, z0 + 0.5), MAT_DARKM)
    prv_cone("PRV_skirt%d" % mark, r * 1.08, r * 0.88, h * 0.14, (cx, cy, z0 + h * 0.07 + 0.3), MAT_GRAYM)
    body_h = h * 0.48
    prv_cyl("PRV_body%d" % mark, r, body_h, (cx, cy, z0 + h * 0.14 + body_h / 2), mat)
    prv_cyl("PRV_band%d" % mark, r + 0.07, h * 0.075, (cx, cy, z0 + h * 0.46), MAT_WHITE)
    nose_h = h * 0.30
    prv_cone("PRV_nose%d" % mark, r, 0.16, nose_h, (cx, cy, z0 + h * 0.70 + nose_h / 2 - h * 0.08), MAT_WHITE)
    for i in range(4):
        a = radians(90 * i + 45)
        bpy.ops.mesh.primitive_cube_add(size=2, location=(cx + math.cos(a) * r * 1.15, cy + math.sin(a) * r * 1.15, z0 + h * 0.10))
        fin = bpy.context.object
        fin.name = "PRV_fin%d_%d" % (mark, i)
        fin.scale = (r * 0.55, 0.16, h * 0.10)
        fin.rotation_euler = (0, 0, a)
        fin.data.materials.append(mat)
        PREVIEW_PARTS.append(fin)


preview_rocket(1, pad_cx, -46)
preview_rocket(2, pad_cx, -16)
preview_rocket(3, pad_cx, 15)
preview_rocket(4, pad_cx, 48)

# ----------------------------------------------------------------------------
# Камера, солнце, мир
# ----------------------------------------------------------------------------
bpy.ops.object.camera_add(location=(10, -160, 280))
cam = bpy.context.object
cam.rotation_euler = (Vector((0, -14, 0)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 36
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(0, 0, 80))
sun = bpy.context.object
sun.rotation_euler = (radians(42), 0, radians(24))
sun.data.energy = 3.0
sun.data.angle = radians(3)

world = bpy.data.worlds.new("IslandWorld")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.36, 0.62, 0.86, 1.0)

scene = bpy.context.scene
scene.render.resolution_x = 1200
scene.render.resolution_y = 980
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
# Standard вместо AgX: сочные игрушечные цвета (AgX сильно их вымывает)
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'

print("MAIN ISLAND built: %d island parts, %d preview parts" % (len(ISLAND_PARTS), len(PREVIEW_PARTS)))
