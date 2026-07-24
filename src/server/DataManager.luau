-- DataManager.luau - persistent money, launcher count, rocket levels, and player preferences
local Players          = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder     = ReplicatedStorage:WaitForChild("Shared", 10)

local Remotes          = require(sharedFolder:WaitForChild("Remotes"))
local Config           = require(sharedFolder:WaitForChild("Config"))

local DataManager = {}

local playerData = {}

local moneyStore = DataStoreService:GetDataStore("TycoonMoney_v3")
local animStore  = DataStoreService:GetDataStore("TycoonAnim_v3")

local function defaultData()
	return {
		money = Config.START_MONEY,
		launchers = Config.START_LAUNCHERS,
		rocketLevels = { 1 },
		airDefense = 0, -- уровень ПВО: 0 = не куплено, 1..MAX_LEVEL
		animEnabled = true,
	}
end

local function load(player)
	local uid = tostring(player.UserId)
	local ok, saved = pcall(function()
		return moneyStore:GetAsync(uid)
	end)

	local data = defaultData()
	if ok and saved then
		data.money = tonumber(saved.money) or data.money
		-- Старые сейвы могли иметь до 6 установок — зажимаем в новый максимум (4).
		data.launchers = math.clamp(tonumber(saved.launchers) or Config.START_LAUNCHERS, Config.START_LAUNCHERS, Config.MAX_LAUNCHERS)
		local savedLevels = type(saved.rocketLevels) == "table" and saved.rocketLevels or {}
		data.rocketLevels = {}
		for index = 1, data.launchers do
			data.rocketLevels[index] = math.clamp(tonumber(savedLevels[index]) or 1, 1, Config.MAX_ROCKET_LEVEL)
		end
		data.airDefense = math.clamp(tonumber(saved.airDefense) or 0, 0, Config.AIR_DEFENSE.MAX_LEVEL)
	end

	local ok2, animVal = pcall(function()
		return animStore:GetAsync(uid)
	end)
	if ok2 and animVal ~= nil then
		data.animEnabled = animVal
	end

	playerData[player] = data
end

local function save(player)
	local data = playerData[player]
	if not data then return end
	local uid = tostring(player.UserId)
	pcall(function()
		moneyStore:UpdateAsync(uid, function()
			return {
				money = data.money,
				launchers = data.launchers,
				rocketLevels = data.rocketLevels,
				airDefense = data.airDefense,
			}
		end)
	end)
	pcall(function()
		animStore:SetAsync(uid, data.animEnabled)
	end)
end

function DataManager.Init()
	Players.PlayerAdded:Connect(function(player)
		load(player)
		task.delay(1, function()
			if player and player.Parent then
				DataManager.SendUpdate(player)
			end
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		load(player)
		task.delay(1, function()
			if player and player.Parent then
				DataManager.SendUpdate(player)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		playerData[player] = nil
	end)

	local setAnim = Remotes.Get("SetAnimSetting")
	setAnim.OnServerEvent:Connect(function(player, enabled)
		local data = playerData[player]
		if data then
			data.animEnabled = enabled == true
			pcall(function()
				animStore:SetAsync(tostring(player.UserId), data.animEnabled)
			end)
		end
	end)

	local getAnim = Remotes.Get("GetAnimSetting")
	getAnim.OnServerInvoke = function(player)
		local data = playerData[player]
		return data and data.animEnabled ~= false
	end
end

function DataManager.GetData(player)
	return playerData[player]
end

function DataManager.GetMoney(player)
	local data = playerData[player]
	return data and data.money or 0
end

function DataManager.AddMoney(player, amount)
	local data = playerData[player]
	if data then
		data.money = math.max(0, data.money + amount)
		DataManager.SendUpdate(player)
	end
end

function DataManager.GetLauncherCount(player)
	local data = playerData[player]
	return data and data.launchers or 0
end

-- Уровень прокачки конкретного стенда (0 — стенд ещё не куплен).
function DataManager.GetLauncherLevel(player, index)
	local data = playerData[player]
	if not data then return 0 end
	if index < 1 or index > data.launchers then return 0 end
	return data.rocketLevels[index] or 1
end

function DataManager.BuyNextLauncher(player)
	local data = playerData[player]
	if not data then return false, "Данные игрока загружаются" end
	if data.launchers >= Config.MAX_LAUNCHERS then
		return false, string.format("Все %d установки уже построены", Config.MAX_LAUNCHERS)
	end
	local nextCount = data.launchers + 1
	local cost = Config.LAUNCHER_COSTS[nextCount]
	if data.money < cost then return false, string.format("Нужно ещё $%d", cost - data.money) end
	data.money -= cost
	data.launchers = nextCount
	data.rocketLevels[nextCount] = 1
	DataManager.SendUpdate(player)
	return true, nextCount
end

-- Прокачка купленного стенда на +1 уровень. Возвращает (true, новыйУровень) либо (false, причина).
function DataManager.UpgradeLauncher(player, index)
	local data = playerData[player]
	if not data then return false, "Данные игрока загружаются" end
	if index < 1 or index > data.launchers then return false, "Сначала купите эту установку" end
	local level = data.rocketLevels[index] or 1
	if level >= Config.MAX_ROCKET_LEVEL then return false, "Максимальный уровень ракеты" end
	local cost = Config.RocketUpgradeCost(level + 1)
	if data.money < cost then return false, string.format("Нужно ещё $%d", cost - data.money) end
	data.money -= cost
	data.rocketLevels[index] = level + 1
	DataManager.SendUpdate(player)
	return true, level + 1
end

-- === ПВО ===

function DataManager.GetAirDefenseLevel(player)
	local data = playerData[player]
	return data and data.airDefense or 0
end

-- Покупка турели ПВО (уровень 0 → 1). Возвращает (true, 1) либо (false, причина).
function DataManager.BuyAirDefense(player)
	local data = playerData[player]
	if not data then return false, "Данные игрока загружаются" end
	if data.airDefense >= 1 then return false, "ПВО уже построено" end
	local cost = Config.AIR_DEFENSE.COST
	if data.money < cost then return false, string.format("Нужно ещё $%d", cost - data.money) end
	data.money -= cost
	data.airDefense = 1
	DataManager.SendUpdate(player)
	return true, 1
end

-- Прокачка ПВО на +1 уровень. Возвращает (true, новыйУровень) либо (false, причина).
function DataManager.UpgradeAirDefense(player)
	local data = playerData[player]
	if not data then return false, "Данные игрока загружаются" end
	if data.airDefense < 1 then return false, "Сначала постройте ПВО" end
	if data.airDefense >= Config.AIR_DEFENSE.MAX_LEVEL then return false, "Максимальный уровень ПВО" end
	local cost = Config.AirDefenseUpgradeCost(data.airDefense + 1)
	if data.money < cost then return false, string.format("Нужно ещё $%d", cost - data.money) end
	data.money -= cost
	data.airDefense += 1
	DataManager.SendUpdate(player)
	return true, data.airDefense
end

function DataManager.SendUpdate(player)
	local data = playerData[player]
	if not data then return end
	local ev = Remotes.Get("UpdateData")
	ev:FireClient(player, {
		money = data.money,
		launchers = data.launchers,
		rocketLevels = data.rocketLevels,
		airDefense = data.airDefense,
		animEnabled = data.animEnabled,
	})
end

return DataManager
