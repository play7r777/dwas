-- Config.luau - shared balance and world configuration
local Config = {}

Config.START_MONEY = 350
Config.FARM_INTERVAL = 4

-- The playable shore sits above a deep Terrain water volume. Roblox automatically
-- puts Humanoids into Swimming state while their character is in this water.
Config.WATER_LEVEL = 18
Config.SEABED_LEVEL = -58
Config.WORLD_SIZE = 2400
Config.PLOT_CENTER_SIZE = 108
Config.SLOT_PLATFORM_SIZE = 46

-- Each launcher stores one rocket and reloads independently after firing.
Config.START_LAUNCHERS = 1
Config.MAX_LAUNCHERS = 6
Config.LAUNCHER_COSTS = { 0, 250, 650, 1500, 3500, 8000 }
Config.ROCKET_RELOAD = 12
Config.ROCKET_DAMAGE = 150
Config.ROCKET_SPEED = 115
Config.ROCKET_ANIM_TIME = 3.2
Config.ROCKET_ARC = 95

-- Прокачка зданий: каждое здание можно улучшать до MAX_BUILDING_LEVEL.
-- Стоимость следующего уровня = базовая цена * UPGRADE_COST_MULT^(текущий уровень),
-- доход здания = базовый доход * уровень.
Config.MAX_BUILDING_LEVEL = 10
Config.UPGRADE_COST_MULT = 1.6

-- Запуск ракеты игроком: ProximityPrompt "Запустить" на ракете (зажать E).
Config.LAUNCH_PROMPT_ACTION = "Запустить"
Config.LAUNCH_PROMPT_HOLD = 0.5

Config.FARM_TYPES = {
	[1] = {
		name = "Пляжный дом",
		cost = 100,
		income = 15,
		maxHp = 120,
		cooldown = 15,
		color = Color3.fromRGB(50, 180, 240),
		material = Enum.Material.SmoothPlastic,
	},
	[2] = {
		name = "Прибрежный коттедж",
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

-- Twelve islands leave enough separation for boat/swimming travel and battle sightlines.
Config.PLOT_POSITIONS = {
	Vector3.new(-540, 28, -540),
	Vector3.new(-180, 28, -620),
	Vector3.new(180, 28, -620),
	Vector3.new(540, 28, -540),
	Vector3.new(-620, 28, -180),
	Vector3.new(620, 28, -180),
	Vector3.new(-620, 28, 180),
	Vector3.new(620, 28, 180),
	Vector3.new(-540, 28, 540),
	Vector3.new(-180, 28, 620),
	Vector3.new(180, 28, 620),
	Vector3.new(540, 28, 540),
}

local radius = 82
Config.SLOT_OFFSETS = {
	[1] = Vector3.new(0, 0, -radius),
	[2] = Vector3.new(radius * math.cos(math.rad(18)), 0, -radius * math.sin(math.rad(18))),
	[3] = Vector3.new(radius * math.cos(math.rad(-54)), 0, radius * math.sin(math.rad(54))),
	[4] = Vector3.new(-radius * math.cos(math.rad(-54)), 0, radius * math.sin(math.rad(54))),
	[5] = Vector3.new(-radius * math.cos(math.rad(18)), 0, -radius * math.sin(math.rad(18))),
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

Config.SILO_OFFSET = Vector3.new(0, 0, 0)
Config.LAUNCHER_OFFSETS = {
	Vector3.new(-18, 0, -8),
	Vector3.new(0, 0, -8),
	Vector3.new(18, 0, -8),
	Vector3.new(-18, 0, 12),
	Vector3.new(0, 0, 12),
	Vector3.new(18, 0, 12),
}

return Config