-- DataManager.luau — деньги, ракеты, настройка анимации
local Players= game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local Remotes        = require(game.ReplicatedStorage.Shared.Remotes)
local Config         = require(game.ReplicatedStorage.Shared.Config)

local DataManager = {}

-- playerData[userId] = { money, rockets, animEnabled }
local playerData = {}

local moneyStore = DataStoreService:GetDataStore("TycoonMoney_v1")
local animStore  = DataStoreService:GetDataStore("TycoonAnim_v1")

local function defaultData()
	return { money = Config.START_MONEY, rockets = 0, animEnabled = true }
end

local function load(player)
	local uid = tostring(player.UserId)
	local ok, saved = pcall(function()
		return moneyStore:GetAsync(uid)
	end)
	local data = defaultData()
	if ok and saved then
		data.money   = saved.moneyor data.money
		data.rockets = saved.rockets or data.rockets
	end
	-- Анимация хранится отдельно
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
		moneyStore:SetAsync(uid, { money = data.money, rockets = data.rockets })
	end)pcall(function()
		animStore:SetAsync(uid, data.animEnabled)
	end)
end

function DataManager.Init()
	Players.PlayerAdded:Connect(function(player)
		load(player)
		--Ждём немного, пока клиент загрузится, потом шлём данные
		task.delay(2, function()
			if player and player.Parent then
				DataManager.SendUpdate(player)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		save(player)
		playerData[player] = nil
	end)

	-- Настройка анимации
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

	-- Покупка ракеты
	local buyRocket = Remotes.Get("BuyRocket")
	buyRocket.OnServerEvent:Connect(function(player)
		local data = playerData[player]
		if not data then return end
		if data.money >= Config.ROCKET_COST then
			data.money= data.money - Config.ROCKET_COST
			data.rockets = data.rockets + 1
			DataManager.SendUpdate(player)
		end
	end)
end

function DataManager.GetData(player)
	return playerData[player]
end

function DataManager.AddMoney(player, amount)
	local data = playerData[player]
	if data then
		data.money = data.money + amount
		DataManager.SendUpdate(player)
	end
end

function DataManager.UseRocket(player)
	local data = playerData[player]
	if not data or data.rockets <= 0 then return false end
	data.rockets = data.rockets - 1
	DataManager.SendUpdate(player)
	return true
end

function DataManager.SendUpdate(player)
	local data = playerData[player]
	if not data then return end
	local ev = Remotes.Get("UpdateData")
	ev:FireClient(player, {
		money        = data.money,
		rockets      = data.rockets,
		animEnabled  = data.animEnabled,})
end

return DataManager