# Pizza Shop — потрёпанная пиццерия (Blender-ассет)

Гранжевая пиццерия по референсу: вывеска PIZZA с куском пиццы, красно-белая
маркиза, витрина, кондиционер, баки, мох и потёки.

## Файлы
- `pizza_shop.py` — генерирует всю сцену с нуля в Blender 4.x (Scripting → Run).
  Камера и свет настроены, F12 — рендер.
- `bake_export.py` — джойнит здание в один меш (центр в origin, низ на z=0),
  запекает все процедурные материалы в атлас 2048px и экспортирует OBJ+MTL+PNG:
  `blender -b --factory-startup -P bake_export.py`
- `pizza_shop.obj` + `pizza_shop.mtl` — готовый меш, 9 056 треугольников
  (лимит Roblox — 10 000 ✓).
- `pizza_shop_texture.png` (атлас 2048px) — бинарник не хранится в репо:
  сгенерируй запуском bake_export.py (папка export/) или возьми из чата.

## Импорт в Roblox Studio
1. Положи `pizza_shop.obj`, `pizza_shop.mtl` и `pizza_shop_texture.png` в одну папку.
2. Studio → Home → **Import 3D** → выбери `pizza_shop.obj` (текстура подцепится сама).
3. Получится один MeshPart с текстурой; модель отцентрована, низ на уровне пола.
