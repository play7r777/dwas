--=============================================
-- Config.luau — настройки баланса игры
-- =============================================
local Config = {}

-- Стартовые деньги игрока
Config.START_MONEY = 500

-- Фарм: каждые N секунд начисляется доход
Config.FARM_INTERVAL = 5-- секунд
Config.FARM_INCOME_BASE = 50  -- монет за тик (уровень 1)

-- Максимальный уровень фермы
Config.MAX_FARM_LEVEL = 5

-- Стоимость улучшения фермы (по уровням)
Config.UPGRADE_COST = {
	[2] = 300,
	[3] = 800,
	[4] = 2000,
	[5] = 5000,
}

-- Доход по уровням фермы (монет за тик)
Config.FARM_INCOME = {
	[1] = 50,
	[2] = 130,
	[3] = 300,
	[4] = 700,
	[5] = 1500,
}

-- HP фермы по уровням
Config.FARM_HP = {
	[1] = 100,
	[2] = 200,
	[3] = 350,
	[4] = 550,
	[5] = 800,
}

-- Цвет фермы по уровням (RGB 0-255 нормализованные)
Config.FARM_COLOR = {
	[1] = Color3.fromRGB(180, 120, 70),   -- дерево
	[2] = Color3.fromRGB(150, 150, 160),  -- камень
	[3] = Color3.fromRGB(80, 120, 200),   -- металл
	[4] = Color3.fromRGB(200, 160, 40),   -- золото
	[5] = Color3.fromRGB(180, 80, 220),   -- магия
}

-- Ракеты
Config.ROCKET_COST= 150-- стоимость одной ракеты
Config.ROCKET_DAMAGE= 80-- урон от одной ракеты
Config.ROCKET_SPEED     = 40    -- скорость анимации (studs/sec)
Config.ROCKET_ANIM_TIME = 2.5   -- максимальная длительность анимации (сек)
Config.ROCKET_ARC= 60    -- высота дуги полёта (studs)

-- Восстановление фермы после уничтожения (секунд)
Config.FARM_REBUILD_TIME = 30

-- Расположение участков (6 штук)
Config.PLOT_POSITIONS = {
	Vector3.new(-130, 0,  -130),
	Vector3.new(   0, 0,  -130),
	Vector3.new( 130, 0,  -130),
	Vector3.new(-130, 0,   130),
	Vector3.new(   0, 0,   130),
	Vector3.new( 130, 0,   130),
}

Config.PLOT_SIZE = 80-- размер стороны участка

return Config