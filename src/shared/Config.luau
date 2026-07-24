-- Config.luau - shared balance and world configuration
local Config = {}

Config.START_MONEY = 350
Config.FARM_INTERVAL = 4

-- The playable shore sits above a deep Terrain water volume. Roblox automatically
-- puts Humanoids into Swimming state while their character is in this water.
Config.WATER_LEVEL = 18
Config.SEABED_LEVEL = -58
Config.WORLD_SIZE = 2600

-- v3: острова стали заметно крупнее (сам пляж, площадки зданий и радиус их разлёта).
Config.PLOT_CENTER_SIZE = 160
Config.SLOT_PLATFORM_SIZE = 56
Config.SLOT_RADIUS = 125

-- Передвижение: обычный бег и спринт на Shift (клиент, см. Sprint.luau).
Config.WALK_SPEED = 16
Config.SPRINT_SPEED = 23

-- Ракетные установки: РОВНО 4 стенда на острове. Первый даётся бесплатно.
-- Покупка следующего стенда и прокачка купленных — наступанием на зелёный круг
-- перед стендом (см. PlotManager rocketPads + RocketManager.OnPadStep).
Config.START_LAUNCHERS = 1
Config.MAX_LAUNCHERS = 4
Config.LAUNCHER_COSTS = { 0, 500, 2000, 6000 }

Config.ROCKET_RELOAD = 12 -- базовый кулдаун на уровне 1 (растёт с прокачкой, см. RocketReloadForLevel)
Config.ROCKET_DAMAGE = 150 -- базовый урон на уровне 1
Config.ROCKET_SPEED = 115
Config.ROCKET_ANIM_TIME = 3.2
Config.ROCKET_ARC = 95

-- Кулдаун ракеты растёт с уровнем ПОСТЕПЕННО и НЕМНОГО (+0.5с за уровень):
-- ур.1 = 12с, ур.15 = 19с. Плата за главный бонус прокачки — радиус поражения.
function Config.RocketReloadForLevel(level)
	return Config.ROCKET_RELOAD + ((level or 1) - 1) * 0.5
end

-- ГЛАВНЫЙ бонус прокачки: радиус поражения ракеты растёт с уровнем.
-- ур.1 = 26 стадов, ур.15 = 47 стадов (почти вдвое шире воронка).
-- Красный круг в прицеле (HudManager) рисуется ровно этим радиусом.
function Config.RocketImpactRadiusForLevel(level)
	return Config.Rocket.ImpactRadius + ((level or 1) - 1) * 1.5
end

-- Прокачка ракеты: каждый стенд качается отдельно. Урон растёт с уровнем,
-- а КАЖДЫЕ 5 УРОВНЕЙ ракета меняет внешний вид (Mark I..IV): 1-4 / 5-9 / 10-14 / 15.
Config.MAX_ROCKET_LEVEL = 15
Config.ROCKET_UPGRADE_BASE = 180
Config.ROCKET_UPGRADE_MULT = 1.45

-- Стоимость прокачки ракеты до уровня nextLevel (nextLevel >= 2).
function Config.RocketUpgradeCost(nextLevel)
	if nextLevel < 2 or nextLevel > Config.MAX_ROCKET_LEVEL then
		return math.huge
	end
	return math.floor(Config.ROCKET_UPGRADE_BASE * (Config.ROCKET_UPGRADE_MULT ^ (nextLevel - 2)) + 0.5)
end

-- Поколение (внешний вид) ракеты для уровня: меняется на уровнях 5, 10 и 15.
function Config.RocketMark(level)
	return math.clamp(math.floor((level or 1) / 5) + 1, 1, 4)
end

function Config.RocketDamageForLevel(level)
	return math.floor(Config.ROCKET_DAMAGE * (1 + 0.25 * ((level or 1) - 1)) + 0.5)
end

-- Прилёт ракеты: если точка удара попадает в радиус ImpactRadius от здания,
-- у здания отключается доход на DisableDuration секунд (см. FarmManager.DisableSlot).
Config.Rocket = {
	DisableDuration = 30,
	ImpactRadius = 26,
}

-- Прокачка зданий: каждое здание можно улучшать до MAX_BUILDING_LEVEL.
-- Стоимость следующего уровня = базовая цена * UPGRADE_COST_MULT^(текущий уровень),
-- доход здания = базовый доход * уровень. Визуально дом растёт: уровень = этажи.
Config.MAX_BUILDING_LEVEL = 10
Config.UPGRADE_COST_MULT = 1.6

-- ПИЦЦЕРИЯ (слот 1): вместо процедурного дома — Blender-меши 5 состояний,
-- уровень 1 = убитая, уровень 5 = новенькая (чем дальше качаешь — тем чище).
-- ПРОКАЧКА ПОСЛЕ 5 УРОВНЯ НЕ ОСТАНАВЛИВАЕТСЯ: деньги/доход растут до
-- MAX_BUILDING_LEVEL, а ВИЗУАЛ после 5 остаётся «чистым» (MAX_LEVEL — потолок
-- только для внешнего вида, см. MaxLevelForSlot и tryBuildLevelMesh).
-- Меши кладутся в Studio: ReplicatedStorage/PizzaShopMeshes/Level1..Level5
-- (Import 3D файлов assets/pizza_shop/pizza_shop_lvlN.obj). Пока мешей нет —
-- играет временный процедурный домик (фолбэк).
Config.PIZZA = {
	MAX_LEVEL = 5, -- потолок ВИЗУАЛА (мешей всего 5), НЕ потолок прокачки
	FOLDER = "PizzaShopMeshes",
	FILE_PREFIX = "pizza_shop_lvl", -- имя файла = имя после Import 3D (переименовывать не надо)
	-- 36 (раньше 24): пиццерия — низкий широкий динер, на 24 стадах она была
	-- крошечной (высота 9.5 стада против 19.7 у кафе). На 36 → высота ~14.3 —
	-- солидно, но всё ещё немного меньше кафе.
	WIDTH = 36,  -- ширина здания в стадах (меш масштабируется пропорционально)
	-- Доворот меша. Фасад OBJ после импорта смотрит по +Z детали, а CFrame.lookAt
	-- целит -Z (LookVector) на центр острова. YAW = 0 → фасад смотрит ВНУТРЬ
	-- острова (на мост). Раньше стояло 180 — пиццерия смотрела наружу, в океан.
	YAW = 0,
}

-- КАФЕ (слот 2): тот же конвейер, что у пиццерии — Blender-меши 5 состояний,
-- уровень 1 = плесень/зелень/грязь, уровень 5 = новенькое чистое.
-- Меши: ReplicatedStorage/CafeMeshes/Level1..Level5 (Import 3D файлов
-- assets/cafe/cafe_lvlN.obj). Пока мешей нет — процедурный фолбэк-домик.
Config.CAFE = {
	MAX_LEVEL = 5,
	FOLDER = "CafeMeshes",
	FILE_PREFIX = "cafe_lvl", -- имя файла = имя после Import 3D (переименовывать не надо)
	WIDTH = 26,
	YAW = 0, -- как у пиццерии: фасад внутрь острова
}

-- Максимальный уровень ПРОКАЧКИ для конкретного слота.
-- Пиццерия качается до общего потолка (после 5 растут только цифры — доход,
-- прочность, цена; визуально остаётся чистый 5-й меш). У кафе потолок пока 5.
function Config.MaxLevelForSlot(slotIndex)
	if slotIndex == 2 then
		return Config.CAFE.MAX_LEVEL
	end
	return Config.MAX_BUILDING_LEVEL
end

-- ЛЕГО-ОСТРОВА из Blender (assets/island): главный остров и под-острова домов.
-- Меши: ReplicatedStorage/IslandMeshes/MainIsland и SubIsland (Import 3D).
-- Пока мешей нет — процедурные песчаные цилиндры (фолбэк).
Config.ISLAND = {
	FOLDER = "IslandMeshes",
	MAIN = "MainIsland",
	SUB = "SubIsland",
	MAIN_WIDTH = 205, -- ширина главного острова в стадах
	SUB_WIDTH = 60,   -- ширина под-острова дома
	-- Доворот главного острова: в меше зона ракет (чёрно-жёлтая лента) справа
	-- (+X), а стенды ракет в игре стоят на СЕВЕРЕ (-Z). YAW = 90 кладёт зону
	-- точно под стенды, газон уходит на юг к спавну.
	YAW = 90,
	-- false (дефолт): игра СРЕЗАЕТ текстуры с острова и красит части плоскими
	-- лего-цветами по именам материалов — гарантированно правильный вид
	-- (свежезалитые текстуры Roblox может отдавать чёрными, пока обрабатывает).
	-- true: оставить текстуры (шипы-точки), Color отбеливается.
	USE_TEXTURES = false,

	-- ОСТРОВ ПО ДЕТАЛЯМ (рекомендуемый путь): отдельные однотонные меши БЕЗ
	-- текстур (assets/island/export_parts.py) — импортируются как пальмы, по
	-- одному файлу, и собираются игрой по этим смещениям (юниты меша; origin =
	-- центр острова на дне, Y вверх). Если детали лежат в ReplicatedStorage —
	-- они В ПРИОРИТЕТЕ над цельным main_island.
	PIECES = {
		FULL_WIDTH = 258.51, -- полная ширина по деталям (для масштаба)
		WALK_TOP = 27.70,    -- высота ходибельной поверхности (верх зелёной плиты)
		-- island_pad (серая площадка ракет) в экспорте — плоскость НУЛЕВОЙ толщины
		-- ровно на высоте зелёной плиты (27.95 = верх island_grass): серый и
		-- зелёный рисовались «в одном пикселе» и мерцали (z-fighting). Поэтому
		-- площадка и её чёрно-жёлтая лента подняты на +0.20 юнита (~0.16 стада):
		-- платформа теперь читается ступенькой над газоном и ни с чем не мерцает.
		LIST = {
			{ name = "island_grass",     off = Vector3.new(-1.253, 27.225, 2.739) },
			{ name = "island_sand",      off = Vector3.new(0.000, 23.174, 0.000) },
			{ name = "island_sand_dark", off = Vector3.new(3.261, 16.174, -2.448) },
			{ name = "island_rock",      off = Vector3.new(-1.253, 2.500, 2.739) },
			{ name = "island_road",      off = Vector3.new(-1.253, 27.630, 2.739) },
			{ name = "island_sidewalk",  off = Vector3.new(-1.253, 27.700, 2.739) },
			{ name = "island_pad",       off = Vector3.new(40.247, 28.150, 2.739) },
			{ name = "island_marking",   off = Vector3.new(-1.253, 27.910, 2.739) },
			{ name = "island_tape",      off = Vector3.new(40.247, 27.960, 2.739) },
		},
	},
	SUB_PIECES = {
		FULL_WIDTH = 66.79,
		WALK_TOP = 15.55,
		LIST = {
			{ name = "sub_grass",     off = Vector3.new(0.000, 14.950, -0.397) },
			{ name = "sub_sand",      off = Vector3.new(0.000, 12.096, 0.000) },
			{ name = "sub_sand_dark", off = Vector3.new(0.747, 9.596, 0.591) },
			{ name = "sub_rock",      off = Vector3.new(0.000, 2.000, -0.397) },
		},
	},
}

-- ЛЕГО-ПАЛЬМЫ из Blender (assets/palm_trees): ровно ДВЕ пальмы на главном
-- острове (PalmA и PalmB смотрят в разные стороны). Меши:
-- ReplicatedStorage/PalmMeshes/PalmA и PalmB. Фолбэк — процедурные пальмы.
Config.PALMS = {
	FOLDER = "PalmMeshes",
	HEIGHT = 24, -- высота пальмы в стадах
	-- name — «красивое» имя, file — имя после Import 3D (подходят оба)
	-- Точки посадки: старые (-58,46) и (52,62) попадали ПРЯМО на кольцевую
	-- дорогу («пальма растёт из трассы»). Новые стоят на внешней зелёной кромке
	-- за тротуаром (газон между дорогой и краем острова): одна на западной
	-- стороне, другая на восточной — вдали от мостов, стендов и кнопок.
	-- offset — точка, куда встаёт СТВОЛ. trunkOff — смещение ствола от центра
	-- bbox меша (юниты меша, из вершин palm_*.obj): Roblox центрирует MeshPart
	-- по bbox кроны, и без компенсации ствол «уезжает» на несколько стадов.
	SPOTS = {
		{ name = "PalmA", file = "palm_a", offset = Vector3.new(-73, 0, 8), yaw = 15, trunkOff = Vector3.new(-3.00, 0, 0.33) },
		{ name = "PalmB", file = "palm_b", offset = Vector3.new(77, 0, 28), yaw = 205, trunkOff = Vector3.new(2.34, 0, -1.82) },
	},
}

-- АКУЛЫ в открытой воде по центру карты (assets/shark — Meshy-модель, ~9.4k
-- треугольников). Меш: ReplicatedStorage/SharkMeshes/shark (или общая папка
-- Meshes / просто ReplicatedStorage — как остальные ассеты). Пока меша нет —
-- процедурная акула из партов (чуть крупнее прежней).
-- Поведение: акула кружит на своём радиусе; если рядом ПЛЫВЁТ игрок — сворачивает
-- к нему и грызёт. Урон декоративно-маленький: DPS = 5 → одна акула съедает
-- игрока (100 HP) ровно за 20 секунд.
Config.SHARKS = {
	COUNT = 16,
	LENGTH = 20,        -- длина акулы в стадах (заметно крупнее прежних ~14)
	FOLDER = "SharkMeshes",
	FILES = { "Shark", "shark" }, -- имена-кандидаты после Import 3D
	-- Нос меша смотрит по -X, вверх +Y (см. assets/shark/README.md). MESH_YAW
	-- доворачивает меш носом вперёд по движению. Import 3D зеркалит ось: с -90
	-- акулы плыли ЗАДОМ НАПЕРЁД, правильное значение — 90 (если после другого
	-- импорта снова хвостом вперёд — верни -90).
	MESH_YAW = 90,
	DPS = 5,            -- урон в секунду: 100 HP / 5 = 20 секунд на игрока
	BITE_RADIUS = 8,    -- в этом радиусе от акулы идёт укус
	BITE_TICK = 0.4,    -- период тика укуса (урон = DPS * BITE_TICK)
	AGGRO_RADIUS = 40,  -- пловца в этом радиусе акула начинает преследовать
	SWIM_SPEED = 14,    -- крейсерская скорость по кругу (стад/сек)
	HUNT_SPEED = 16,    -- скорость погони (чуть быстрее пловца)
}

-- ЛЕГО-РАКЕТЫ НА СТЕНДАХ (assets/rockets): Mk1..Mk4 — чем дальше стенд, тем
-- крупнее ракета. Меши: rocket_mk1..rocket_mk4 (или Mk1..Mk4) в
-- ReplicatedStorage/Meshes / RocketMeshes. Пока мешей нет — процедурные
-- ракеты RocketFactory (летящая ракета всегда процедурная — там трейлы/звук).
Config.ROCKETS = {
	FOLDER = "RocketMeshes",
	-- Смещение ОСИ ракеты от центра bbox меша (юниты меша, XZ). Roblox
	-- центрирует MeshPart по bbox, а у mk1/mk2 несимметричные плавники тянут
	-- bbox вбок — ракета стояла НЕ по центру круга-платформы. Числа сняты с
	-- вершин rocket_mkN.obj (центроид носа = истинная ось). Игра сдвигает КРУГ
	-- под фактическую ось ракеты (и выравнивает летящий меш по траектории).
	AXIS_OFF = {
		[1] = Vector3.new(0, 0, 0.615),
		[2] = Vector3.new(0, 0, 0.799),
		[3] = Vector3.zero,
		[4] = Vector3.zero,
	},
}

-- ПВО-МИНИГАН (assets/air_defense): сбивает вражеские ракеты на подлёте.
-- Покупка/прокачка — зелёный круг рядом с турелью (на газоне). Уровень растёт →
-- турель стреляет ЧАЩЕ и попадает ЧАЩЕ, но гарантий нет: может сбить, а может
-- и промазать. Меши: ReplicatedStorage/AirDefenseMeshes/{Base,Head,Barrels}
-- (Import 3D частей air_defense_*.obj), фолбэк — процедурная турель.
Config.AIR_DEFENSE = {
	MAX_LEVEL = 5,
	COST = 750,                 -- покупка турели
	UPGRADE_BASE = 900,         -- цена прокачки до ур.2
	UPGRADE_MULT = 1.65,        -- геометрический рост цены
	-- Чем выше уровень — тем ЧАЩЕ очередь (видно глазами) и тем ВЫШЕ шанс
	-- попадания за выстрел: ур.1 = 30%, ур.5 = 60% (линейно между ними).
	-- Промах — это настоящий промах: пуля летит МИМО ракеты и уходит в небо.
	FIRE_INTERVAL = { 1.40, 1.05, 0.75, 0.50, 0.30 }, -- сек между выстрелами
	HIT_CHANCE = { 0.30, 0.375, 0.45, 0.525, 0.60 },  -- шанс сбить за выстрел
	RANGE = 230,                -- радиус перехвата от турели (в стадах)
	-- ПУЛИ: видимые трассеры, вылетают из дула. Меш assets/air_defense/bullet.obj
	-- (ReplicatedStorage/Meshes, имя «bullet»), фолбэк — неоновая капсула.
	BULLET = {
		SPEED = 320,             -- скорость пули (стад/сек)
		LENGTH = 2.6,            -- длина трассера в стадах
		LIFETIME = 1.6,          -- жизнь пули после вылета (промах улетает в небо)
		FILES = { "Bullet", "bullet", "ad_bullet" },
		HIT_RADIUS = 7,          -- пуля «догнала» ракету ближе этого — ракета сбита
	},
	OFFSET = Vector3.new(-34, 0, 44), -- позиция на газоне (юго-запад от центра)
	HEIGHT = 14,                -- высота турели в стадах
	FOLDER = "AirDefenseMeshes",
	-- Геометрия Blender-мешей (в юнитах меша, см. assets/air_defense):
	-- пивот башни/стволов и смещения bbox — чтобы собрать три части в турель.
	MESH = {
		TOTAL_H = 11.6,                        -- полная высота турели в юнитах
		HEAD_PIVOT_Z = 8.1,                    -- высота пивота башни
		BARREL_PIVOT = Vector3.new(0, 0, 4.6), -- пивот стволов от пивота башни (+Z = вперёд)
		MUZZLE = Vector3.new(0, 0, 8.0),       -- дуло от пивота стволов
		-- bbox-центры частей относительно их пивотов (числа из экспортных OBJ:
		-- Roblox центрирует MeshPart по bbox, поэтому ставим детали со сдвигом).
		BASE_BB = Vector3.new(0, 3.400, 0),
		HEAD_BB = Vector3.new(0.526, 1.305, 0.312),
		BARR_BB = Vector3.new(0, 0, 3.972),
	},
}

-- Стоимость прокачки ПВО до уровня nextLevel (nextLevel >= 2).
function Config.AirDefenseUpgradeCost(nextLevel)
	if nextLevel < 2 or nextLevel > Config.AIR_DEFENSE.MAX_LEVEL then
		return math.huge
	end
	return math.floor(Config.AIR_DEFENSE.UPGRADE_BASE * (Config.AIR_DEFENSE.UPGRADE_MULT ^ (nextLevel - 2)) + 0.5)
end

-- Запуск ракеты: игрок подходит к своей установке и удерживает E, после чего камера
-- сразу переносится к вражеским островам (без бокового меню, см. HudManager).
-- Сервер независимо проверяет, что стрелок реально стоит рядом со своей установкой.
Config.LAUNCH_MAX_DISTANCE = 30

Config.FARM_TYPES = {
	[1] = {
		-- Бывший «Пляжный дом»: теперь это ПИЦЦЕРИЯ с Blender-мешами 5 уровней.
		name = "Пиццерия",
		cost = 100,
		income = 15,
		maxHp = 120,
		cooldown = 15,
		color = Color3.fromRGB(50, 180, 240),
		material = Enum.Material.SmoothPlastic,
	},
	[2] = {
		-- Бывший «Прибрежный коттедж»: теперь это КАФЕ с Blender-мешами 5 уровней
		-- (уровень 1 = плесень и грязь, уровень 5 = новенькое).
		name = "Кафе",
		cost = 500,
		income = 60,
		maxHp = 280,
		cooldown = 25,
		color = Color3.fromRGB(180, 70, 240),
		material = Enum.Material.Neon,
	},
	[3] = {
		name = "Семейная вилла",
		cost = 2200,
		income = 220,
		maxHp = 550,
		cooldown = 40,
		color = Color3.fromRGB(60, 220, 100),
		material = Enum.Material.Glass,
	},
	[4] = {
		name = "Панорамный особняк",
		cost = 8000,
		income = 750,
		maxHp = 1000,
		cooldown = 60,
		color = Color3.fromRGB(255, 140, 30),
		material = Enum.Material.Neon,
	},
	[5] = {
		name = "Островная резиденция",
		cost = 30000,
		income = 2500,
		maxHp = 2000,
		cooldown = 90,
		color = Color3.fromRGB(240, 50, 180),
		material = Enum.Material.ForceField,
	},
}

-- === ЗАЩИТА ОТ «МЁРТВОГО ТУПИКА» ЭКОНОМИКИ ===
-- Раньше можно было на старте случайно наступить на прокачку ракеты вместо
-- покупки первой фармилки и остаться без денег НАВСЕГДА (дохода нет — купить
-- нечего — доход не появится). Двойная страховка:
--  1. РЕЗЕРВ: пока на острове нет НИ ОДНОГО доходного здания, любая трата на
--     ракеты/ПВО, после которой не хватит на Пиццерию, блокируется
--     (см. FarmManager.CanSpendKeepingReserve).
--  2. ПОСОБИЕ: если зданий нет и денег меньше цены Пиццерии (в т.ч. старые
--     «сломанные» сейвы с $0) — раз в FARM_INTERVAL капает RESCUE_INCOME,
--     пока не наберётся ровно на Пиццерию. Тупик самоизлечивается.
Config.ECONOMY_SAFETY = {
	RESCUE_INCOME = 10, -- $ за тик FARM_INTERVAL (10/4с → с нуля до Пиццерии за 40с)
}

-- ВОСЕМЬ островов кольцом вокруг ПУСТОГО центра карты (центральный остров убран,
-- в открытой воде по центру кружат акулы).
-- Y=12 (раньше 28): остров ОПУЩЕН так, что песчаная кайма-лесенка встречает воду
-- (газон ~4 стада над водой) — из воды на пляж теперь просто выходишь по
-- лего-ступеням, деревянный трап больше не нужен и удалён (см. PlotManager).
local RING_RADIUS = 660
Config.PLOT_POSITIONS = {}
for i = 1, 8 do
	local a = math.rad((i - 1) * 45)
	Config.PLOT_POSITIONS[i] = Vector3.new(
		math.floor(math.cos(a) * RING_RADIUS + 0.5),
		12,
		math.floor(math.sin(a) * RING_RADIUS + 0.5)
	)
end

local slotRadius = Config.SLOT_RADIUS
Config.SLOT_OFFSETS = {
	[1] = Vector3.new(0, 0, -slotRadius),
	[2] = Vector3.new(slotRadius * math.cos(math.rad(18)), 0, -slotRadius * math.sin(math.rad(18))),
	[3] = Vector3.new(slotRadius * math.cos(math.rad(-54)), 0, slotRadius * math.sin(math.rad(54))),
	[4] = Vector3.new(-slotRadius * math.cos(math.rad(-54)), 0, slotRadius * math.sin(math.rad(54))),
	[5] = Vector3.new(-slotRadius * math.cos(math.rad(18)), 0, -slotRadius * math.sin(math.rad(18))),
}

-- ПИЦЦЕРИЯ И КАФЕ ЖИВУТ НА ГЛАВНОМ ОСТРОВЕ: зелёный прямоугольник газона в
-- рамке жёлтого пунктира (мировые координаты газона: x −50..50, z 6..54 от
-- центра острова; там же стоит ПВО на западе и точка спавна на юге).
-- Слот из этого списка строится ПРЯМО на газоне: без моста, под-острова,
-- фонарей и кустов. offset — центр здания, padOffset — зелёная кнопка
-- покупки/прокачки (стоит между зданием и спавном), фасад смотрит на кнопку.
-- Слоты 3-5 (вилла/особняк/резиденция) остаются на под-островах вокруг.
Config.LAWN_SLOTS = {
	[1] = { offset = Vector3.new(27, 0, 20), padOffset = Vector3.new(27, 0, 39) },  -- пиццерия: восточная половина газона
	[2] = { offset = Vector3.new(-15, 0, 20), padOffset = Vector3.new(-15, 0, 39) }, -- кафе: западная половина, южнее ПВО
}

-- Стоимость улучшения здания слота до уровня nextLevel (nextLevel >= 2).
function Config.UpgradeCost(tier, nextLevel)
	local base = Config.FARM_TYPES[tier]
	if not base then return math.huge end
	-- цена растёт геометрически: base.cost * mult^(nextLevel-1)
	return math.floor(base.cost * (Config.UPGRADE_COST_MULT ^ (nextLevel - 1)) + 0.5)
end

-- Доход здания слота на заданном уровне.
function Config.IncomeForLevel(tier, level)
	local base = Config.FARM_TYPES[tier]
	if not base then return 0 end
	return base.income * level
end

-- Стенды ракет — линия на северной стороне острова. Зелёный круг покупки/прокачки
-- стоит ПЕРЕД каждым стендом, на LAUNCHER_PAD_FORWARD ближе к центру острова.
Config.LAUNCHER_OFFSETS = {
	Vector3.new(-36, 0, -30),
	Vector3.new(-12, 0, -30),
	Vector3.new(12, 0, -30),
	Vector3.new(36, 0, -30),
}
Config.LAUNCHER_PAD_FORWARD = 16

return Config
