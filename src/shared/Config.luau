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

Config.ROCKET_RELOAD = 12
Config.ROCKET_DAMAGE = 150 -- базовый урон на уровне 1
Config.ROCKET_SPEED = 115
Config.ROCKET_ANIM_TIME = 3.2
Config.ROCKET_ARC = 95

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
-- После 5 уровня контента пока НЕТ, поэтому слот 1 выше 5 не прокачивается.
-- Меши кладутся в Studio: ReplicatedStorage/PizzaShopMeshes/Level1..Level5
-- (Import 3D файлов assets/pizza_shop/pizza_shop_lvlN.obj). Пока мешей нет —
-- играет временный процедурный домик (фолбэк).
Config.PIZZA = {
	MAX_LEVEL = 5,
	FOLDER = "PizzaShopMeshes",
	FILE_PREFIX = "pizza_shop_lvl", -- имя файла = имя после Import 3D (переименовывать не надо)
	WIDTH = 24,  -- ширина здания в стадах (меш масштабируется пропорционально)
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

-- Максимальный уровень для конкретного слота (у пиццерии и кафе свои потолки).
function Config.MaxLevelForSlot(slotIndex)
	if slotIndex == 1 then
		return Config.PIZZA.MAX_LEVEL
	end
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
}

-- ЛЕГО-ПАЛЬМЫ из Blender (assets/palm_trees): ровно ДВЕ пальмы на главном
-- острове (PalmA и PalmB смотрят в разные стороны). Меши:
-- ReplicatedStorage/PalmMeshes/PalmA и PalmB. Фолбэк — процедурные пальмы.
Config.PALMS = {
	FOLDER = "PalmMeshes",
	HEIGHT = 24, -- высота пальмы в стадах
	-- name — «красивое» имя, file — имя после Import 3D (подходят оба)
	SPOTS = {
		{ name = "PalmA", file = "palm_a", offset = Vector3.new(-58, 0, 46), yaw = 15 },
		{ name = "PalmB", file = "palm_b", offset = Vector3.new(52, 0, 62), yaw = 205 },
	},
}

-- ЛЕГО-РАКЕТЫ НА СТЕНДАХ (assets/rockets): Mk1..Mk4 — чем дальше стенд, тем
-- крупнее ракета. Меши: rocket_mk1..rocket_mk4 (или Mk1..Mk4) в
-- ReplicatedStorage/Meshes / RocketMeshes. Пока мешей нет — процедурные
-- ракеты RocketFactory (летящая ракета всегда процедурная — там трейлы/звук).
Config.ROCKETS = {
	FOLDER = "RocketMeshes",
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
	FIRE_INTERVAL = { 1.40, 1.05, 0.75, 0.50, 0.30 }, -- сек между выстрелами
	HIT_CHANCE = { 0.18, 0.24, 0.30, 0.36, 0.42 },    -- шанс сбить за выстрел
	RANGE = 230,                -- радиус перехвата от турели (в стадах)
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

-- ВОСЕМЬ островов кольцом вокруг ПУСТОГО центра карты (центральный остров убран,
-- в открытой воде по центру кружат акулы).
local RING_RADIUS = 660
Config.PLOT_POSITIONS = {}
for i = 1, 8 do
	local a = math.rad((i - 1) * 45)
	Config.PLOT_POSITIONS[i] = Vector3.new(
		math.floor(math.cos(a) * RING_RADIUS + 0.5),
		28,
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
