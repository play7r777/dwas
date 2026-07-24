# Импорт мешей в Studio — БЕЗ переименований

Код понимает **имена файлов как есть** (то, как Import 3D сам называет
результат) и ищет их в **одной общей папке**. Ничего переименовывать не надо.

## Шаги

1. **Текстуры.** Один раз преврати `.b64` в настоящие PNG — любой способ:
   - распакуй `dwas_v3.3.0_assets.zip` из чата поверх `assets/`, ИЛИ
   - из корня репы: `python3 tools/decode_textures.py`

2. **Папка.** В Studio (Explorer) создай в **ReplicatedStorage** папку с именем
   `Meshes` (правый клик по ReplicatedStorage → Insert Object → Folder).

3. **Импорт.** Home → **Import 3D** → выбери файл → Import. Повтори для каждого:

   | Файл | Что это |
   |---|---|
   | `assets/cafe/cafe_lvl1.obj` … `cafe_lvl5.obj` | кафе, 5 уровней |
   | `assets/pizza_shop/pizza_shop_lvl1.obj` … `lvl5.obj` | пиццерия, 5 уровней |
   | `assets/palm_trees/palm_a.obj`, `palm_b.obj` | две пальмы |
   | `assets/island/main_island.obj` | главный остров |
   | `assets/island/sub_island.obj` | под-остров домов |
   | `assets/air_defense/air_defense_base.obj`, `_head.obj`, `_barrels.obj` | ПВО (3 части) |

   Текстура подцепится сама (PNG лежит рядом с OBJ). Имя результата
   (`cafe_lvl1`, `palm_a`, `main_island`, …) **не трогай**.

4. **Перетащи** всё импортированное в `ReplicatedStorage/Meshes`. Всё.

## Что подхватится само

- слот 1 — пиццерия по уровням, слот 2 — кафе по уровням (1 грязное → 5 чистое)
- главный остров-меш вместо цилиндров (зона ракет ляжет на север, под стенды)
- под-остров под каждым домом
- ровно две пальмы на газоне
- турель ПВО (база/башня/стволы, башня целится, стволы крутятся)

Чего нет в папке — играет процедурным фолбэком, ошибок не будет.

## Детали (если что-то не встало)

- Старый способ тоже работает: отдельные папки `PizzaShopMeshes`, `CafeMeshes`,
  `IslandMeshes`, `PalmMeshes`, `AirDefenseMeshes` с «красивыми» именами
  (`Level1..5`, `PalmA/PalmB`, `MainIsland/SubIsland`, `Base/Head/Barrels`).
- Регистр букв не важен. Model-обёртка от Import 3D — ок, код достанет меш сам.
- `main_island` Import 3D скорее всего разобьёт на несколько MeshPart по
  материалам — это нормально, оставь их внутри модели `main_island`.
- Если фасад пиццерии/кафе смотрит не туда — `Config.PIZZA.YAW` /
  `Config.CAFE.YAW` (0 ↔ 180). Если зона ракет не на севере — `Config.ISLAND.YAW`.
- `rocket_mk1..4.obj` — внешка для стендов, к коду пока не подключены (стенды
  строит RocketFactory процедурно).
