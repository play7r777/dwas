-- DataManager.luau - persistent money, launcher count, and player preferences
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
	return { money = Config.START_MONEY, launchers = Config.START_LAUNCHERS, animEnabled = true }
end

local function load(player)
	local uid = tostring(player.UserId)
	local ok, saved = pcall(function()
		return moneyStore:GetAsync(uid)
	end)

	local data = defaultData()
	if ok and saved then
		data.money = tonumber(saved.money) or data.money
		data.launchers = math.clamp(tonumber(saved.launchers) or Config.START_LAUNCHERS, Config.START_LAUNCHERS, Config.MAX_LAUNCHERS)
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
			return { money = data.money, launchers = data.launchers }
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

function DataManager.BuyNextLauncher(player)
	local data = playerData[player]
	if not data then return false, "Данные игрока загружаются" end
	if data.launchers >= Config.MAX_LAUNCHERS then return false, "Все 6 установок уже построены" end
	local nextCount = data.launchers + 1
	local cost = Config.LAUNCHER_COSTS[nextCount]
	if data.money < cost then return false, string.format("Нужно ещё $%d", cost - data.money) end
	data.money -= cost
	data.launchers = nextCount
	DataManager.SendUpdate(player)
	return true, nextCount
end

function DataManager.SendUpdate(player)
	local data = playerData[player]
	if not data then return end
	local ev = Remotes.Get("UpdateData")
	ev:FireClient(player, {
		money = data.money,
		launchers = data.launchers,
		animEnabled = data.animEnabled,
	})
end

return DataManager