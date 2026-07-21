-- Config.luau — настройки баланса игры
local Config = {}

Config.START_MONEY      = 500
Config.FARM_INTERVAL= 5
Config.FARM_INCOME_BASE = 50
Config.MAX_FARM_LEVEL   = 5

Config.UPGRADE_COST = { [2]=300, [3]=800, [4]=2000, [5]=5000 }
Config.FARM_INCOME= { [1]=50, [2]=130, [3]=300, [4]=700, [5]=1500 }
Config.FARM_HP= { [1]=100, [2]=200, [3]=350, [4]=550, [5]=800 }

Config.FARM_COLOR = {
	[1] = Color3.fromRGB(180, 120, 70),
	[2] = Color3.fromRGB(150, 150, 160),
	[3] = Color3.fromRGB(80,120, 200),
	[4] = Color3.fromRGB(200, 160, 40),
	[5] = Color3.fromRGB(180, 80,  220),
}

Config.ROCKET_COST= 150
Config.ROCKET_DAMAGE    = 80
Config.ROCKET_SPEED     = 40
Config.ROCKET_ANIM_TIME = 2.5
Config.ROCKET_ARC= 60

Config.FARM_REBUILD_TIME = 30

--6участков, карта 800x800
Config.PLOT_POSITIONS = {
	Vector3.new(-200, 0, -200),
	Vector3.new(   0, 0, -200),
	Vector3.new( 200, 0, -200),
	Vector3.new(-200, 0,  200),
	Vector3.new(   0, 0,  200),
	Vector3.new( 200, 0,  200),
}

Config.PLOT_SIZE = 110

return Config