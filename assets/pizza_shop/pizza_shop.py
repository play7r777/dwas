# pizza_shop.py — процедурная генерация гранжевой пиццерии в Blender (bpy)
#
# Как запустить: Blender → вкладка Scripting → New → вставить этот файл → Run Script (Alt+P)
# Или из консоли:  blender -b --factory-startup -P pizza_shop.py
#
# Сцена: одноэтажная коробка-пиццерия с вывеской PIZZA и куском пиццы,
# красно-белой маркизой, витриной со стеклянной дверью, кондиционером,
# зелёными мусорными баками, жёлтыми столбиками, тротуаром и асфальтом.
# Камера и солнце уже настроены — можно сразу жать Render (F12).
#
# Протестировано на Blender 4.x (использует только стабильные API).

import bpy
import math
import os
from math import radians
from mathutils import Vector

# ----------------------------------------------------------------------------
# УРОВЕНЬ ПРОКАЧКИ ПИЦЦЕРИИ: 1 = убитая, 5 = новенькая.
# Меняй константу или задавай через переменную окружения PIZZA_LEVEL.
# Чем выше уровень — тем чище здание (прокачка = ремонт).
# ----------------------------------------------------------------------------
LEVEL = max(1, min(5, int(os.environ.get("PIZZA_LEVEL", "3"))))
DIRT = (5 - LEVEL) / 4.0  # 0.0 (чистая) .. 1.0 (полностью убитая)


def L(clean, dirty):
    """Интерполяция цвета между чистым и грязным по уровню DIRT."""
    return tuple(c + (d - c) * DIRT for c, d in zip(clean, dirty))


# ----------------------------------------------------------------------------
# Очистка сцены
# ----------------------------------------------------------------------------
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

# ----------------------------------------------------------------------------
# Материалы
# ----------------------------------------------------------------------------

def make_mat(name, color, rough=0.8, metallic=0.0, grunge=None, grunge_scale=6.0):
    """Простой материал. Если задан grunge (цвет грязи) — базовый цвет
    смешивается с ним через Noise → ColorRamp (потёртость/разводы)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    links = m.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if grunge:
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = grunge_scale
        noise.inputs["Detail"].default_value = 8.0
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.33
        ramp.color_ramp.elements[0].color = (*grunge, 1.0)
        ramp.color_ramp.elements[1].position = 0.72
        ramp.color_ramp.elements[1].color = (*color, 1.0)
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    return m


def make_brick_mat(name):
    """Потрёпанная крашеная кирпичная кладка: Brick Texture + вертикальные потёки
    грязи + тёмный замшелый низ здания (как на референсе)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    links = m.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9

    coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (2.2, 2.2, 2.2)
    # Поворот текстурного пространства: ряды кирпича ложатся ГОРИЗОНТАЛЬНО
    # на фасаде и боках (без поворота на фасаде получаются вертикальные полосы).
    mapping.inputs["Rotation"].default_value = (radians(90), 0, 0)
    brick = nodes.new("ShaderNodeTexBrick")
    brick.inputs["Color1"].default_value = (*L((0.66, 0.63, 0.57), (0.55, 0.52, 0.46)), 1.0)  # кирпич
    brick.inputs["Color2"].default_value = (*L((0.55, 0.51, 0.45), (0.44, 0.40, 0.34)), 1.0)  # тёмный кирпич
    brick.inputs["Mortar"].default_value = (*L((0.44, 0.43, 0.40), (0.34, 0.33, 0.30)), 1.0)  # шов
    brick.inputs["Scale"].default_value = 6.0
    brick.inputs["Mortar Size"].default_value = 0.006
    brick.offset = 0.5
    links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], brick.inputs["Vector"])

    # Вертикальные потёки: шум, растянутый по вертикали (малый масштаб по Z)
    smap = nodes.new("ShaderNodeMapping")
    smap.inputs["Scale"].default_value = (10.0, 10.0, 1.3)
    snoise = nodes.new("ShaderNodeTexNoise")
    snoise.inputs["Scale"].default_value = 3.0
    snoise.inputs["Detail"].default_value = 8.0
    sramp = nodes.new("ShaderNodeValToRGB")
    sramp.color_ramp.elements[0].position = 0.50
    sramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    sramp.color_ramp.elements[1].position = 0.63
    sramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    links.new(coord.outputs["Generated"], smap.inputs["Vector"])
    links.new(smap.outputs["Vector"], snoise.inputs["Vector"])
    links.new(snoise.outputs["Fac"], sramp.inputs["Fac"])

    # Замшелый грязный низ: градиент по высоте здания
    sep = nodes.new("ShaderNodeSeparateXYZ")
    gramp = nodes.new("ShaderNodeValToRGB")
    gramp.color_ramp.elements[0].position = 0.05
    gramp.color_ramp.elements[0].color = (1, 1, 1, 1)
    gramp.color_ramp.elements[1].position = 0.35
    gramp.color_ramp.elements[1].color = (0, 0, 0, 1)
    links.new(coord.outputs["Generated"], sep.inputs["Vector"])
    links.new(sep.outputs["Z"], gramp.inputs["Fac"])

    # Маска грязи = (потёки*0.55 + низ) * DIRT — на 5 уровне стены чистые
    mul = nodes.new("ShaderNodeMath")
    mul.operation = 'MULTIPLY'
    mul.inputs[1].default_value = 0.55
    add = nodes.new("ShaderNodeMath")
    add.operation = 'ADD'
    add.use_clamp = True
    links.new(sramp.outputs["Color"], mul.inputs[0])
    links.new(mul.outputs["Value"], add.inputs[0])
    links.new(gramp.outputs["Color"], add.inputs[1])
    dirtscale = nodes.new("ShaderNodeMath")
    dirtscale.operation = 'MULTIPLY'
    dirtscale.inputs[1].default_value = DIRT
    links.new(add.outputs["Value"], dirtscale.inputs[0])

    # Смешение кирпича с грязью (ShaderNodeMix, data_type RGBA:
    # inputs[0]=Factor, [6]=A, [7]=B; outputs[2]=Result)
    mixn = nodes.new("ShaderNodeMix")
    mixn.data_type = 'RGBA'
    mixn.inputs[7].default_value = (0.14, 0.145, 0.105, 1.0)  # грязь/мох
    links.new(dirtscale.outputs["Value"], mixn.inputs[0])
    links.new(brick.outputs["Color"], mixn.inputs[6])
    links.new(mixn.outputs[2], bsdf.inputs["Base Color"])
    return m


# Каждый материал задаётся парой (чистый цвет, грязный цвет) — реальный цвет
# интерполируется по уровню DIRT. На 5 уровне грязь совпадает с базой (её нет),
# на 1 уровне здание полностью убитое.
MAT_WALL      = make_brick_mat("WallBrick")
MAT_ROOF      = make_mat("Roof", L((0.13, 0.13, 0.13), (0.10, 0.10, 0.10)), rough=0.95, grunge=L((0.13, 0.13, 0.13), (0.05, 0.05, 0.05)))
# Окантовка: свежая терракота → тёмная бурая с рыжими пятнами коррозии
MAT_RUST      = make_mat("RustTrim", L((0.24, 0.11, 0.05), (0.055, 0.030, 0.018)), rough=0.95, grunge=L((0.24, 0.11, 0.05), (0.17, 0.085, 0.035)), grunge_scale=6)
MAT_SIGNBAND  = make_mat("SignBand", L((0.80, 0.79, 0.74), (0.64, 0.62, 0.56)), rough=0.85, grunge=L((0.80, 0.79, 0.74), (0.34, 0.32, 0.26)), grunge_scale=3)
MAT_RED       = make_mat("SignRed", L((0.56, 0.04, 0.04), (0.50, 0.04, 0.04)), rough=0.55, grunge=L((0.56, 0.04, 0.04), (0.30, 0.03, 0.03)), grunge_scale=7)
MAT_AWN_RED   = make_mat("AwningRed", L((0.52, 0.06, 0.05), (0.40, 0.05, 0.04)), rough=0.9, grunge=L((0.52, 0.06, 0.05), (0.19, 0.04, 0.03)), grunge_scale=5)
MAT_AWN_WHITE = make_mat("AwningWhite", L((0.85, 0.83, 0.78), (0.62, 0.58, 0.50)), rough=0.9, grunge=L((0.85, 0.83, 0.78), (0.36, 0.33, 0.26)), grunge_scale=5)
MAT_GLASS     = make_mat("DarkGlass", (0.012, 0.014, 0.016), rough=0.08 + 0.25 * DIRT, metallic=0.12, grunge=L((0.012, 0.014, 0.016), (0.05, 0.05, 0.045)), grunge_scale=4)
MAT_FRAME     = make_mat("FrameBronze", L((0.16, 0.11, 0.07), (0.13, 0.09, 0.06)), rough=0.55, metallic=0.5, grunge=L((0.16, 0.11, 0.07), (0.07, 0.05, 0.03)), grunge_scale=8)
MAT_CONCRETE  = make_mat("Concrete", L((0.46, 0.45, 0.43), (0.38, 0.37, 0.35)), rough=0.95, grunge=L((0.46, 0.45, 0.43), (0.22, 0.21, 0.19)), grunge_scale=4)
MAT_ASPHALT   = make_mat("Asphalt", (0.045, 0.045, 0.048), rough=0.95, grunge=(0.02, 0.02, 0.022), grunge_scale=3)
MAT_AC        = make_mat("ACMetal", L((0.60, 0.62, 0.63), (0.46, 0.48, 0.48)), rough=0.6, metallic=0.4, grunge=L((0.60, 0.62, 0.63), (0.24, 0.22, 0.20)), grunge_scale=5)
MAT_DARKMETAL = make_mat("DarkMetal", (0.09, 0.09, 0.10), rough=0.5, metallic=0.6)
MAT_GREEN     = make_mat("DumpsterGreen", L((0.06, 0.26, 0.09), (0.05, 0.20, 0.07)), rough=0.8, grunge=L((0.06, 0.26, 0.09), (0.03, 0.10, 0.04)), grunge_scale=5)
MAT_YELLOW    = make_mat("BollardYellow", L((0.85, 0.66, 0.06), (0.80, 0.60, 0.05)), rough=0.65, grunge=L((0.85, 0.66, 0.06), (0.42, 0.30, 0.06)), grunge_scale=6)
MAT_CHEESE    = make_mat("Cheese", (0.87, 0.66, 0.23), rough=0.65, grunge=L((0.87, 0.66, 0.23), (0.62, 0.44, 0.15)), grunge_scale=8)
MAT_CRUST     = make_mat("Crust", (0.50, 0.30, 0.11), rough=0.75)
MAT_PEPPERONI = make_mat("Pepperoni", (0.42, 0.07, 0.05), rough=0.6)
MAT_WHITE     = make_mat("SignWhite", L((0.85, 0.85, 0.82), (0.78, 0.78, 0.74)), rough=0.65, grunge=L((0.85, 0.85, 0.82), (0.55, 0.54, 0.50)), grunge_scale=6)
MAT_MOSS      = make_mat("Moss", (0.030, 0.050, 0.022), rough=1.0, grunge=(0.018, 0.032, 0.014), grunge_scale=10)
MAT_BAG       = make_mat("TrashBag", (0.04, 0.04, 0.05), rough=0.45)
MAT_CARDBOARD = make_mat("Cardboard", (0.36, 0.25, 0.13), rough=0.9, grunge=(0.24, 0.16, 0.08), grunge_scale=7)
MAT_PLANK     = make_mat("OldPlank", (0.30, 0.22, 0.13), rough=0.95, grunge=(0.18, 0.13, 0.08), grunge_scale=7)

# ----------------------------------------------------------------------------
# Хелперы геометрии
# ----------------------------------------------------------------------------

def box(name, size, loc, mat, rot=(0, 0, 0), parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = Vector(size)
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj


def cyl(name, r, depth, loc, mat, rot=(0, 0, 0), verts=16, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, rotation=rot, vertices=verts)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    if parent:
        obj.parent = parent
    return obj


def sphere(name, r, loc, mat, parent=None):
    # Низкая плотность: суммарный меш должен влезать в лимит Roblox (10k треугольников)
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=14, ring_count=8)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    if parent:
        obj.parent = parent
    return obj


def prism(name, pts_xz, thickness, loc, mat, parent=None):
    """Призма из 2D-контура в плоскости XZ, выдавленная вдоль Y (лицом к -Y)."""
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
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    return obj

# ----------------------------------------------------------------------------
# Здание (8 x 6 x 4 м, фасад смотрит на -Y)
# ----------------------------------------------------------------------------

box("Building", (8, 6, 4), (0, 0, 2), MAT_WALL)
box("Foundation", (8.3, 6.3, 0.35), (0, 0, 0.17), MAT_CONCRETE)
box("RoofSlab", (8.15, 6.15, 0.12), (0, 0, 4.05), MAT_ROOF)

# Ржавая окантовка парапета и передние углы
box("ParapetF", (8.3, 0.18, 0.14), (0, -3.02, 4.12), MAT_RUST)
box("ParapetB", (8.3, 0.18, 0.14), (0, 3.02, 4.12), MAT_RUST)
box("ParapetL", (0.18, 6.3, 0.14), (-4.02, 0, 4.12), MAT_RUST)
box("ParapetR", (0.18, 6.3, 0.14), (4.02, 0, 4.12), MAT_RUST)
box("CornerTrimL", (0.16, 0.16, 4.0), (-4.0, -3.0, 2.0), MAT_RUST)
box("CornerTrimR", (0.16, 0.16, 4.0), (4.0, -3.0, 2.0), MAT_RUST)

# ----------------------------------------------------------------------------
# Вывеска: белёсая панель, красные буквы PIZZA и кусок пиццы
# ----------------------------------------------------------------------------

box("SignBand", (7.7, 0.14, 1.15), (0, -3.06, 3.25), MAT_SIGNBAND)
box("SignTrimTop", (7.7, 0.16, 0.06), (0, -3.07, 3.85), MAT_RUST)
box("SignTrimBot", (7.7, 0.16, 0.06), (0, -3.07, 2.65), MAT_RUST)

bpy.ops.object.text_add(location=(-1.05, -3.16, 2.83), rotation=(radians(90), 0, 0))
txt = bpy.context.object
txt.name = "PizzaText"
txt.data.body = "PIZZA"
txt.data.size = 0.92
txt.data.extrude = 0.055
txt.data.bevel_depth = 0.004
txt.data.align_x = 'CENTER'
txt.data.materials.append(MAT_RED)

# Кусок пиццы (наклонён, как на вывеске)
slice_root = bpy.data.objects.new("SliceRoot", None)
bpy.context.collection.objects.link(slice_root)
slice_root.location = (2.05, -3.17, 3.18)
slice_root.rotation_euler = (0, radians(-30), 0)

prism("SliceCheese", [(-0.40, 0.42), (0.40, 0.34), (0.02, -0.62)], 0.08, (0, 0, 0), MAT_CHEESE, parent=slice_root)
box("SliceCrust", (0.88, 0.10, 0.16), (0, 0, 0.42), MAT_CRUST, rot=(0, radians(-5.7), 0), parent=slice_root)
for i, (px, pz) in enumerate([(-0.13, 0.13), (0.11, 0.24), (0.02, -0.10), (-0.02, 0.33)]):
    cyl("Pepperoni_%d" % i, 0.085, 0.03, (px, -0.05, pz), MAT_PEPPERONI, rot=(radians(90), 0, 0), parent=slice_root)

# ----------------------------------------------------------------------------
# Красно-белая маркиза (10 полос со свесом)
# ----------------------------------------------------------------------------

awning_stripes = []
for i in range(10):
    x = -3.105 + i * 0.69
    mat = MAT_AWN_RED if i % 2 == 0 else MAT_AWN_WHITE
    stripe = box("Awning_%d" % i, (0.69, 1.2, 0.045), (x, -3.52, 2.36), mat, rot=(radians(20), 0, 0))
    awning_stripes.append(stripe)
    box("AwningValance_%d" % i, (0.69, 0.04, 0.18), (x, -4.06, 2.07), mat)

# На 1 уровне одна полоса маркизы провисла (сломана)
if DIRT >= 0.95:
    broken = awning_stripes[7]
    broken.rotation_euler = (radians(48), 0, radians(-4))
    broken.location = (broken.location.x, -3.45, 2.22)

# ----------------------------------------------------------------------------
# Витрина: окна, стеклянная дверь, ступенька
# ----------------------------------------------------------------------------

def window(cx, cz, w, h, mullions=0):
    box("WinGlass", (w - 0.1, 0.05, h - 0.1), (cx, -3.03, cz), MAT_GLASS)
    box("WinTop", (w, 0.07, 0.07), (cx, -3.06, cz + h / 2 - 0.035), MAT_FRAME)
    box("WinBot", (w, 0.07, 0.07), (cx, -3.06, cz - h / 2 + 0.035), MAT_FRAME)
    box("WinL", (0.07, 0.07, h), (cx - w / 2 + 0.035, -3.06, cz), MAT_FRAME)
    box("WinR", (0.07, 0.07, h), (cx + w / 2 - 0.035, -3.06, cz), MAT_FRAME)
    for k in range(mullions):
        mx = cx - w / 2 + (k + 1) * w / (mullions + 1)
        box("WinMullion", (0.05, 0.06, h - 0.1), (mx, -3.05, cz), MAT_FRAME)

window(-2.0, 1.8, 2.7, 1.7, mullions=2)   # большая витрина слева
window(2.1, 1.8, 1.5, 1.7, mullions=1)    # окно справа от двери

# Дверь
box("DoorGlass", (1.0, 0.05, 2.2), (0.1, -3.03, 1.15), MAT_GLASS)
box("DoorL", (0.08, 0.08, 2.35), (-0.44, -3.06, 1.18), MAT_FRAME)
box("DoorR", (0.08, 0.08, 2.35), (0.64, -3.06, 1.18), MAT_FRAME)
box("DoorTop", (1.16, 0.08, 0.08), (0.1, -3.06, 2.32), MAT_FRAME)
box("DoorHeader", (1.16, 0.08, 0.12), (0.1, -3.06, 2.42), MAT_FRAME)
box("DoorHandle", (0.05, 0.05, 0.7), (0.45, -3.10, 1.2), MAT_DARKMETAL)
box("DoorKickplate", (1.0, 0.03, 0.25), (0.1, -3.06, 0.16), MAT_DARKMETAL)
box("DoorSign", (0.28, 0.02, 0.4), (0.28, -3.07, 1.7), MAT_WHITE)
box("DoorSignHeader", (0.28, 0.022, 0.1), (0.28, -3.071, 1.86), MAT_RED)
box("DoorStep", (1.5, 0.55, 0.16), (0.1, -3.28, 0.08), MAT_CONCRETE)

# ----------------------------------------------------------------------------
# Кондиционер на правой стене + труба
# ----------------------------------------------------------------------------

box("ACBody", (0.42, 0.95, 0.62), (4.21, -1.5, 3.0), MAT_AC)
box("ACBracket", (0.35, 0.6, 0.05), (4.18, -1.5, 2.65), MAT_RUST)
bpy.ops.mesh.primitive_torus_add(major_radius=0.2, minor_radius=0.02, location=(4.44, -1.5, 3.0), rotation=(0, radians(90), 0))
ring = bpy.context.object
ring.name = "ACFanRing"
ring.data.materials.append(MAT_DARKMETAL)
bpy.ops.object.shade_smooth()
cyl("ACFanHub", 0.05, 0.03, (4.44, -1.5, 3.0), MAT_DARKMETAL, rot=(0, radians(90), 0))
cyl("WallPipe", 0.03, 3.6, (4.05, 0.6, 1.8), MAT_AC)

# ----------------------------------------------------------------------------
# Мусорные баки справа
# ----------------------------------------------------------------------------

box("DumpsterBody", (1.35, 0.95, 1.15), (5.0, -0.9, 0.65), MAT_GREEN)
box("DumpsterLid", (1.4, 1.0, 0.08), (5.0, -0.88, 1.27), MAT_GREEN, rot=(radians(6), 0, 0))
for dx in (-0.55, 0.55):
    for dy in (-0.35, 0.35):
        cyl("DumpsterWheel", 0.07, 0.05, (5.0 + dx, -0.9 + dy, 0.07), MAT_DARKMETAL, rot=(0, radians(90), 0))
box("Bin2Body", (0.65, 0.85, 1.25), (6.0, -0.75, 0.7), MAT_GREEN)
box("Bin2Lid", (0.7, 0.9, 0.07), (6.0, -0.73, 1.36), MAT_GREEN, rot=(radians(-5), 0, 0))

# ----------------------------------------------------------------------------
# Жёлтые столбики перед фасадом
# ----------------------------------------------------------------------------

for bx in (-2.6, 2.9):
    cyl("Bollard", 0.075, 0.76, (bx, -4.0, 0.38), MAT_YELLOW)
    sphere("BollardCap", 0.078, (bx, -4.0, 0.77), MAT_YELLOW)

# ----------------------------------------------------------------------------
# Гранж-детали ПО УРОВНЯМ: чем ниже уровень — тем больше мусора и запустения.
#   lvl 4-5: чисто, ничего нет
#   lvl 1-3: мох у основания, мешки, коробка
#   lvl 1-2: ещё больше мусора
#   lvl 1:   заколоченное окно + провисшая маркиза (выше)
# ----------------------------------------------------------------------------

if DIRT >= 0.45:  # уровни 1-3
    for i, (mx, my) in enumerate([(-3.2, -3.02), (-0.9, -3.02), (2.5, -3.02), (4.02, -0.6), (4.02, 1.8)]):
        moss = sphere("Moss_%d" % i, 0.3, (mx, my, 0.38), MAT_MOSS)
        moss.dimensions = (1.0, 0.35, 0.5)

    bag1 = sphere("TrashBag1", 0.3, (5.55, -1.7, 0.28), MAT_BAG)
    bag1.dimensions = (0.75, 0.65, 0.55)
    bag2 = sphere("TrashBag2", 0.3, (6.1, -1.55, 0.24), MAT_BAG)
    bag2.dimensions = (0.6, 0.55, 0.45)
    box("CardboardBox", (0.55, 0.45, 0.38), (4.55, -2.25, 0.19), MAT_CARDBOARD, rot=(0, 0, radians(18)))

if DIRT >= 0.7:  # уровни 1-2: мусора заметно больше
    bag3 = sphere("TrashBag3", 0.3, (3.6, -3.6, 0.26), MAT_BAG)
    bag3.dimensions = (0.7, 0.6, 0.5)
    bag4 = sphere("TrashBag4", 0.3, (4.15, -3.35, 0.22), MAT_BAG)
    bag4.dimensions = (0.55, 0.5, 0.42)
    box("CardboardBox2", (0.5, 0.4, 0.32), (-3.6, -3.5, 0.16), MAT_CARDBOARD, rot=(0, 0, radians(-24)))
    box("CardboardBox3", (0.45, 0.5, 0.3), (5.3, -2.4, 0.15), MAT_CARDBOARD, rot=(0, 0, radians(40)))
    for i, (mx, my) in enumerate([(1.2, -3.02), (-2.2, -3.02)]):
        moss = sphere("MossX_%d" % i, 0.3, (mx, my, 0.35), MAT_MOSS)
        moss.dimensions = (1.3, 0.4, 0.55)

if DIRT >= 0.95:  # уровень 1: правое окно заколочено досками (наперекосяк)
    box("WindowPlank1", (1.75, 0.06, 0.28), (2.1, -3.10, 1.95), MAT_PLANK, rot=(0, radians(-7), 0))
    box("WindowPlank2", (1.75, 0.06, 0.28), (2.1, -3.11, 1.5), MAT_PLANK, rot=(0, radians(5), 0))

# ----------------------------------------------------------------------------
# Земля: асфальт + бетонный тротуар
# ----------------------------------------------------------------------------

bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
ground = bpy.context.object
ground.name = "Ground"
ground.data.materials.append(MAT_ASPHALT)
box("Sidewalk", (12, 3.4, 0.06), (0, -4.4, 0.03), MAT_CONCRETE)

# ----------------------------------------------------------------------------
# Камера, солнце, мир (ракурс как на референсе)
# ----------------------------------------------------------------------------

# Ракурс как на референсе: вид спереди-справа, видна правая стена с кондиционером и баками
bpy.ops.object.camera_add(location=(7.2, -9.8, 1.85))
cam = bpy.context.object
cam.name = "ShopCamera"
target = Vector((-0.6, -0.6, 2.15))
cam.rotation_euler = (target - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 33
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(0, 0, 10))
sun = bpy.context.object
sun.rotation_euler = (radians(55), 0, radians(15))
sun.data.energy = 3.5
sun.data.color = (1.0, 0.95, 0.85)
sun.data.angle = radians(3)

world = bpy.context.scene.world
if world is None:
    world = bpy.data.worlds.new("World")
    bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.45, 0.55, 0.68, 1.0)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.7

print("Пиццерия сгенерирована! Камера и свет настроены — жми F12 для рендера.")

# ----------------------------------------------------------------------------
# (Опционально) Экспорт для Roblox / игровых движков — раскомментируй нужное:
# ----------------------------------------------------------------------------
# bpy.ops.object.select_all(action='SELECT')
# bpy.ops.wm.obj_export(filepath="pizza_shop.obj", export_selected_objects=True)
# bpy.ops.export_scene.fbx(filepath="pizza_shop.fbx", use_selection=True)
