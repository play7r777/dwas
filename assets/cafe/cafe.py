# cafe.py — процедурная генерация кафе в Blender (bpy), 5 уровней чистоты.
#
# Как запустить: Blender → вкладка Scripting → New → вставить этот файл → Run Script (Alt+P)
# Или из консоли:  CAFE_LEVEL=3 blender -b --factory-startup -P cafe.py
#
# Сцена: уютное кафе-бокс с большой витриной, стеклянной дверью, полосатой
# бирюзовой маркизой, вывеской CAFE с чашкой, парапетом с лего-шипами,
# кондиционером на крыше и кадками у входа. Фасад смотрит на -Y (как у пиццерии).
#
# УРОВНИ: 1 = убитое (плесень, зелень, мусор, заколоченное окно, порванная
# маркиза) ... 5 = новенькое чистое. Уровень — константа LEVEL или env CAFE_LEVEL.
#
# Протестировано на Blender 4.x.

import bpy
import os
import math
from math import radians
from mathutils import Vector

LEVEL = max(1, min(5, int(os.environ.get("CAFE_LEVEL", "3"))))
DIRT = (5 - LEVEL) / 4.0  # 0.0 (чистое) .. 1.0 (полностью убитое)


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
    """Простой материал; grunge — цвет грязи, подмешивается шумом по DIRT."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    links = m.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metallic
    if grunge and DIRT > 0.03:
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = grunge_scale
        noise.inputs["Detail"].default_value = 8.0
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = max(0.02, 0.30 * DIRT)
        ramp.color_ramp.elements[0].color = (*grunge, 1.0)
        ramp.color_ramp.elements[1].position = min(0.95, 0.30 * DIRT + 0.42)
        ramp.color_ramp.elements[1].color = (*color, 1.0)
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    return m


def make_wall_mat(name):
    """Крашеная кирпичная стена кафе: кремовая покраска, а по мере DIRT —
    зеленоватая плесень пятнами, вертикальные потёки и замшелый низ."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    links = m.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.9

    coord = nodes.new("ShaderNodeTexCoord")
    mapping = nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (2.4, 2.4, 2.4)
    mapping.inputs["Rotation"].default_value = (radians(90), 0, 0)
    brick = nodes.new("ShaderNodeTexBrick")
    brick.inputs["Color1"].default_value = (*L((0.88, 0.83, 0.72), (0.58, 0.60, 0.48)), 1.0)
    brick.inputs["Color2"].default_value = (*L((0.82, 0.76, 0.64), (0.50, 0.52, 0.40)), 1.0)
    brick.inputs["Mortar"].default_value = (*L((0.70, 0.66, 0.58), (0.40, 0.42, 0.34)), 1.0)
    brick.inputs["Scale"].default_value = 6.5
    brick.inputs["Mortar Size"].default_value = 0.006
    brick.offset = 0.5
    links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
    links.new(mapping.outputs["Vector"], brick.inputs["Vector"])

    # ПЛЕСЕНЬ: крупные зеленоватые пятна (главная фишка грязных уровней)
    mnoise = nodes.new("ShaderNodeTexNoise")
    mnoise.inputs["Scale"].default_value = 2.1
    mnoise.inputs["Detail"].default_value = 7.0
    mramp = nodes.new("ShaderNodeValToRGB")
    mramp.color_ramp.elements[0].position = 0.52
    mramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    mramp.color_ramp.elements[1].position = 0.70
    mramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    links.new(coord.outputs["Generated"], mnoise.inputs["Vector"])
    links.new(mnoise.outputs["Fac"], mramp.inputs["Fac"])

    # Вертикальные потёки под крышей
    smap = nodes.new("ShaderNodeMapping")
    smap.inputs["Scale"].default_value = (10.0, 10.0, 1.2)
    snoise = nodes.new("ShaderNodeTexNoise")
    snoise.inputs["Scale"].default_value = 3.2
    snoise.inputs["Detail"].default_value = 8.0
    sramp = nodes.new("ShaderNodeValToRGB")
    sramp.color_ramp.elements[0].position = 0.52
    sramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    sramp.color_ramp.elements[1].position = 0.64
    sramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    links.new(coord.outputs["Generated"], smap.inputs["Vector"])
    links.new(smap.outputs["Vector"], snoise.inputs["Vector"])
    links.new(snoise.outputs["Fac"], sramp.inputs["Fac"])

    # Замшелый низ (градиент по высоте)
    sep = nodes.new("ShaderNodeSeparateXYZ")
    gramp = nodes.new("ShaderNodeValToRGB")
    gramp.color_ramp.elements[0].position = 0.04
    gramp.color_ramp.elements[0].color = (1, 1, 1, 1)
    gramp.color_ramp.elements[1].position = 0.34
    gramp.color_ramp.elements[1].color = (0, 0, 0, 1)
    links.new(coord.outputs["Generated"], sep.inputs["Vector"])
    links.new(sep.outputs["Z"], gramp.inputs["Fac"])

    # Итоговая маска плесени/грязи = (пятна*0.8 + потёки*0.45 + низ*0.9) * DIRT
    def scaled(out_socket, k):
        mul = nodes.new("ShaderNodeMath")
        mul.operation = 'MULTIPLY'
        mul.inputs[1].default_value = k
        links.new(out_socket, mul.inputs[0])
        return mul

    m1 = scaled(mramp.outputs["Color"], 0.80 * DIRT)
    m2 = scaled(sramp.outputs["Color"], 0.45 * DIRT)
    m3 = scaled(gramp.outputs["Color"], 0.90 * DIRT)
    add1 = nodes.new("ShaderNodeMath"); add1.operation = 'ADD'
    links.new(m1.outputs[0], add1.inputs[0]); links.new(m2.outputs[0], add1.inputs[1])
    add2 = nodes.new("ShaderNodeMath"); add2.operation = 'ADD'; add2.use_clamp = True
    links.new(add1.outputs[0], add2.inputs[0]); links.new(m3.outputs[0], add2.inputs[1])

    # Цвет плесени: зеленовато-болотный
    mixm = nodes.new("ShaderNodeMix")
    mixm.data_type = 'RGBA'
    mixm.inputs["B"].default_value = (0.28, 0.36, 0.20, 1.0)
    links.new(brick.outputs["Color"], mixm.inputs["A"])
    links.new(add2.outputs[0], mixm.inputs["Factor"])
    links.new(mixm.outputs["Result"], bsdf.inputs["Base Color"])
    return m


MAT_WALL     = make_wall_mat("CafeWall")
MAT_CONCRETE = make_mat("Concrete", L((0.62, 0.62, 0.60), (0.40, 0.41, 0.37)), grunge=(0.30, 0.31, 0.27), grunge_scale=4.0)
MAT_ROOF     = make_mat("Roof", L((0.36, 0.37, 0.38), (0.24, 0.26, 0.23)), grunge=(0.16, 0.19, 0.14), grunge_scale=3.0)
MAT_TRIM     = make_mat("TrimWood", L((0.26, 0.16, 0.09), (0.16, 0.11, 0.07)), rough=0.7)
MAT_AWN_A    = make_mat("AwningTeal", L((0.04, 0.45, 0.42), (0.22, 0.30, 0.26)), rough=0.85, grunge=(0.15, 0.20, 0.16), grunge_scale=9.0)
MAT_AWN_B    = make_mat("AwningCream", L((0.92, 0.90, 0.82), (0.52, 0.52, 0.42)), rough=0.85, grunge=(0.36, 0.38, 0.30), grunge_scale=9.0)
MAT_GLASS    = make_mat("Glass", L((0.55, 0.72, 0.75), (0.36, 0.42, 0.38)), rough=0.15, metallic=0.1)
MAT_FRAME    = make_mat("Frame", L((0.16, 0.17, 0.18), (0.12, 0.13, 0.12)), rough=0.5, metallic=0.4)
MAT_SIGN     = make_mat("SignPanel", L((0.13, 0.15, 0.16), (0.10, 0.11, 0.10)), rough=0.6)
MAT_LETTERS  = make_mat("Letters", L((0.95, 0.90, 0.78), (0.62, 0.60, 0.48)), rough=0.4)
MAT_CUP      = make_mat("Cup", L((0.93, 0.92, 0.88), (0.60, 0.60, 0.52)), rough=0.35)
MAT_METAL    = make_mat("Metal", L((0.55, 0.57, 0.58), (0.34, 0.36, 0.34)), rough=0.45, metallic=0.6, grunge=(0.28, 0.24, 0.16), grunge_scale=7.0)
MAT_PLANTER  = make_mat("Planter", L((0.45, 0.26, 0.15), (0.30, 0.20, 0.12)), rough=0.9)
MAT_PLANT    = make_mat("Plant", L((0.22, 0.48, 0.20), (0.36, 0.32, 0.14)), rough=0.9)
MAT_FLOWER   = make_mat("Flower", (0.85, 0.20, 0.25), rough=0.7)
MAT_TRASH    = make_mat("Trash", (0.13, 0.14, 0.15), rough=0.9)
MAT_PLANK    = make_mat("Plank", (0.42, 0.32, 0.20), rough=0.95, grunge=(0.24, 0.19, 0.12), grunge_scale=10.0)
MAT_GROUND   = make_mat("GroundMat", (0.45, 0.47, 0.44), rough=1.0)
MAT_SIDEWALK = make_mat("SidewalkMat", (0.58, 0.58, 0.56), rough=1.0)
MAT_STUD     = make_mat("Studs", L((0.80, 0.78, 0.72), (0.48, 0.49, 0.42)), rough=0.6)

# ----------------------------------------------------------------------------
# Помощники геометрии
# ----------------------------------------------------------------------------

def box(name, size, loc, mat, rot=None):
    bpy.ops.mesh.primitive_cube_add(size=2, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    if rot:
        obj.rotation_euler = rot
    obj.data.materials.append(mat)
    return obj


def cyl(name, r, depth, loc, mat, rot=None, verts=20):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=verts)
    obj = bpy.context.object
    obj.name = name
    if rot:
        obj.rotation_euler = rot
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def sphere(name, r, loc, mat, squash=1.0):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=12, ring_count=7)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (1, 1, squash)
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj


def torus(name, r, tr, loc, mat, rot=None):
    bpy.ops.mesh.primitive_torus_add(major_radius=r, minor_radius=tr, location=loc,
                                     major_segments=18, minor_segments=8)
    obj = bpy.context.object
    obj.name = name
    if rot:
        obj.rotation_euler = rot
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return obj

# ----------------------------------------------------------------------------
# Окружение (в игру НЕ едет — bake_export его удаляет)
# ----------------------------------------------------------------------------

box("Ground", (26, 26, 0.1), (0, 0, -0.08), MAT_GROUND)
box("Sidewalk", (12, 4.2, 0.12), (0, -4.6, -0.02), MAT_SIDEWALK)

# ----------------------------------------------------------------------------
# Здание (7.4 x 5.6 x 4.0 м, фасад смотрит на -Y)
# ----------------------------------------------------------------------------
W, D, H = 7.4, 5.6, 4.0

box("Building", (W, D, H), (0, 0, H / 2), MAT_WALL)
box("Foundation", (W + 0.3, D + 0.3, 0.35), (0, 0, 0.17), MAT_CONCRETE)
box("RoofSlab", (W + 0.15, D + 0.15, 0.14), (0, 0, H + 0.06), MAT_ROOF)

# Парапет с рядом лего-шипов
box("ParapetF", (W + 0.3, 0.22, 0.30), (0, -(D / 2 + 0.04), H + 0.22), MAT_CONCRETE)
box("ParapetB", (W + 0.3, 0.22, 0.30), (0, (D / 2 + 0.04), H + 0.22), MAT_CONCRETE)
box("ParapetL", (0.22, D + 0.3, 0.30), (-(W / 2 + 0.04), 0, H + 0.22), MAT_CONCRETE)
box("ParapetR", (0.22, D + 0.3, 0.30), ((W / 2 + 0.04), 0, H + 0.22), MAT_CONCRETE)
for i in range(9):
    x = -3.3 + i * 0.825
    cyl("StudF_%d" % i, 0.14, 0.10, (x, -(D / 2 + 0.04), H + 0.42), MAT_STUD, verts=10)
    cyl("StudB_%d" % i, 0.14, 0.10, (x, (D / 2 + 0.04), H + 0.42), MAT_STUD, verts=10)

# ----------------------------------------------------------------------------
# Фасад: витрина, дверь, маркиза, вывеска
# ----------------------------------------------------------------------------
FY = -(D / 2)  # плоскость фасада

def window(cx, cz, w, h, mullions=1, face_y=FY, rot_z=0.0):
    box("WinFrame", (w + 0.16, 0.10, h + 0.16), (cx, face_y - 0.05, cz), MAT_FRAME, rot=(0, 0, rot_z))
    box("WinGlass", (w, 0.06, h), (cx, face_y - 0.07, cz), MAT_GLASS, rot=(0, 0, rot_z))
    for k in range(mullions):
        mx = cx - w / 2 + (k + 1) * w / (mullions + 1)
        box("WinMul", (0.07, 0.09, h), (mx, face_y - 0.09, cz), MAT_FRAME, rot=(0, 0, rot_z))
    box("WinSill", (w + 0.3, 0.24, 0.10), (cx, face_y - 0.10, cz - h / 2 - 0.09), MAT_CONCRETE, rot=(0, 0, rot_z))

# Большая витрина слева и дверь справа
window(-1.55, 1.75, 2.9, 1.85, mullions=2)
box("DoorGlass", (1.05, 0.06, 2.25), (1.55, FY - 0.06, 1.18), MAT_GLASS)
box("DoorFrameL", (0.10, 0.10, 2.4), (0.98, FY - 0.08, 1.25), MAT_FRAME)
box("DoorFrameR", (0.10, 0.10, 2.4), (2.12, FY - 0.08, 1.25), MAT_FRAME)
box("DoorFrameT", (1.25, 0.10, 0.10), (1.55, FY - 0.08, 2.42), MAT_FRAME)
box("DoorHandle", (0.05, 0.06, 0.5), (1.20, FY - 0.13, 1.15), MAT_METAL)
box("DoorStep", (1.5, 0.7, 0.12), (1.55, FY - 0.4, 0.06), MAT_CONCRETE)

# Маркиза: 7 наклонных полос (бирюзовая/кремовая)
awning_slats = []
for i in range(7):
    x = -2.97 + i * 0.99
    mat = MAT_AWN_A if i % 2 == 0 else MAT_AWN_B
    slat = box("Awning_%d" % i, (1.0, 1.5, 0.07), (x, FY - 0.72, 3.02), mat, rot=(radians(24), 0, 0))
    awning_slats.append(slat)
box("AwningBar", (7.1, 0.08, 0.10), (0, FY - 1.40, 2.73), MAT_METAL)

# На 1-2 уровнях маркиза повреждена: одна полоса провисла/сорвана
if LEVEL <= 2:
    broken = awning_slats[4]
    broken.rotation_euler = (radians(74), 0, radians(6))
    broken.location.z -= 0.42
    broken.location.y -= 0.12
if LEVEL == 1:
    gone = awning_slats[1]
    gone.rotation_euler = (radians(88), 0, radians(-4))
    gone.location = (gone.location.x - 0.2, FY - 1.15, 0.55)  # валяется у стены

# Вывеска CAFE + чашка
box("SignBand", (6.9, 0.14, 1.0), (0, FY - 0.06, 3.72), MAT_SIGN)
box("SignTrimT", (6.9, 0.16, 0.06), (0, FY - 0.07, 4.24), MAT_TRIM)
box("SignTrimB", (6.9, 0.16, 0.06), (0, FY - 0.07, 3.20), MAT_TRIM)
bpy.ops.object.text_add(location=(-1.7, FY - 0.15, 3.38), rotation=(radians(90), 0, 0))
txt = bpy.context.object
txt.name = "CafeText"
txt.data.body = "CAFE"
txt.data.size = 0.78
txt.data.extrude = 0.045
txt.data.materials.append(MAT_LETTERS)
# Чашка кофе на вывеске: цилиндр + ручка-тор + блюдце
cyl("SignCup", 0.26, 0.34, (2.15, FY - 0.20, 3.75), MAT_CUP, verts=16)
torus("SignCupHandle", 0.15, 0.045, (2.46, FY - 0.20, 3.75), MAT_CUP, rot=(radians(90), 0, 0))
cyl("SignSaucer", 0.36, 0.05, (2.15, FY - 0.20, 3.55), MAT_CUP, verts=16)

# Боковые окна (по два на каждой стене)
for sy in (-1.4, 1.4):
    box("SideFrameR", (0.10, 1.6, 1.26), (W / 2 + 0.05, sy, 2.4), MAT_FRAME)
    box("SideGlassR", (0.06, 1.44, 1.1), (W / 2 + 0.07, sy, 2.4), MAT_GLASS)
    box("SideFrameL", (0.10, 1.6, 1.26), (-(W / 2) - 0.05, sy, 2.4), MAT_FRAME)
    box("SideGlassL", (0.06, 1.44, 1.1), (-(W / 2) - 0.07, sy, 2.4), MAT_GLASS)

# Задняя дверь и окно
box("BackDoor", (1.0, 0.08, 2.1), (-1.8, D / 2 + 0.04, 1.1), MAT_TRIM)
box("BackWinFrame", (1.3, 0.10, 0.9), (1.6, D / 2 + 0.05, 2.5), MAT_FRAME)
box("BackWinGlass", (1.16, 0.06, 0.76), (1.6, D / 2 + 0.07, 2.5), MAT_GLASS)

# ----------------------------------------------------------------------------
# Крыша: кондиционер, труба-вытяжка
# ----------------------------------------------------------------------------
ac = box("AC", (1.3, 0.9, 0.75), (-2.1, 1.2, H + 0.50), MAT_METAL)
box("ACGrill", (0.06, 0.7, 0.55), (-1.42, 1.2, H + 0.50), MAT_FRAME)
cyl("VentPipe", 0.16, 1.5, (2.4, 1.8, H + 0.80), MAT_METAL, verts=12)
cyl("VentCap", 0.26, 0.12, (2.4, 1.8, H + 1.58), MAT_FRAME, verts=12)

# ----------------------------------------------------------------------------
# У входа: кадки с растениями (живые ↔ засохшие), меловая доска (на чистых),
# мусор (на грязных), заколоченное окно (уровень 1)
# ----------------------------------------------------------------------------
for px in (-3.2, 3.2):
    box("Planter", (0.8, 0.8, 0.55), (px, FY - 0.75, 0.28), MAT_PLANTER)
    if LEVEL >= 3:
        sphere("PlantBush", 0.42, (px, FY - 0.75, 0.75), MAT_PLANT, squash=0.85)
        if LEVEL >= 4:
            for fi, (fx, fy) in enumerate(((0.18, 0.1), (-0.15, -0.12), (0.02, 0.2))):
                sphere("Flower", 0.09, (px + fx, FY - 0.75 + fy, 0.95), MAT_FLOWER)
    else:
        # засохшие палки
        for si in range(3):
            cyl("DeadStick", 0.03, 0.6, (px + (si - 1) * 0.16, FY - 0.75, 0.75), MAT_TRIM,
                rot=(radians((si - 1) * 18), radians(si * 12), 0), verts=6)

if LEVEL >= 4:
    # Меловая доска-штендер у двери
    box("BoardA", (0.62, 0.05, 0.9), (2.8, FY - 0.85, 0.48), MAT_TRIM, rot=(radians(-12), 0, 0))
    box("BoardB", (0.62, 0.05, 0.9), (2.8, FY - 1.05, 0.48), MAT_TRIM, rot=(radians(12), 0, 0))
    box("BoardFace", (0.5, 0.02, 0.66), (2.8, FY - 0.895, 0.50), MAT_SIGN, rot=(radians(-12), 0, 0))

if LEVEL <= 2:
    # Мусорные мешки и валяющийся стакан
    sphere("Trash1", 0.42, (-3.1, FY - 0.55, 0.30), MAT_TRASH, squash=0.72)
    sphere("Trash2", 0.34, (-2.5, FY - 0.75, 0.24), MAT_TRASH, squash=0.70)
    cyl("LitterCup", 0.10, 0.26, (0.4, FY - 1.3, 0.10), MAT_CUP, rot=(0, radians(90), 0), verts=10)
if LEVEL == 1:
    sphere("Trash3", 0.38, (2.6, FY - 0.5, 0.26), MAT_TRASH, squash=0.66)
    # Заколоченная витрина: две доски крест-накрест
    box("PlankA", (3.1, 0.06, 0.28), (-1.55, FY - 0.16, 1.9), MAT_PLANK, rot=(0, radians(14), 0))
    box("PlankB", (3.1, 0.06, 0.28), (-1.55, FY - 0.18, 1.6), MAT_PLANK, rot=(0, radians(-11), 0))

# Кондиционер на фасаде (обжитость, уровни 1-3 — старый ржавый)
if LEVEL <= 3:
    box("WallAC", (0.9, 0.5, 0.6), (-3.05, FY - 0.28, 2.55), MAT_METAL)
    box("WallACGrill", (0.7, 0.05, 0.4), (-3.05, FY - 0.56, 2.55), MAT_FRAME)

# ----------------------------------------------------------------------------
# Камера, солнце, мир — можно сразу жать Render (F12)
# ----------------------------------------------------------------------------
bpy.ops.object.camera_add(location=(8.6, -10.6, 5.2))
cam = bpy.context.object
cam.rotation_euler = (Vector((0.2, 0.4, 1.9)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.lens = 34
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(0, 0, 12))
sun = bpy.context.object
sun.rotation_euler = (radians(50), 0, radians(28))
sun.data.energy = 3.4
sun.data.angle = radians(4)

world = bpy.data.worlds.new("CafeWorld")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.47, 0.58, 0.70, 1.0)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0

scene = bpy.context.scene
scene.render.resolution_x = 1000
scene.render.resolution_y = 800
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 32
scene.cycles.use_denoising = True
# Standard вместо AgX: сочные игрушечные цвета (AgX сильно их вымывает)
scene.view_settings.view_transform = 'Standard'
scene.view_settings.look = 'None'

print("CAFE LEVEL %d built (DIRT=%.2f)" % (LEVEL, DIRT))
