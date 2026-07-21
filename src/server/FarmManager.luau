-- FarmManager.luau — строительство, улучшение и уничтожение ферм
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config            = require(ReplicatedStorage.Shared.Config)
local Remotes           = require(ReplicatedStorage.Shared.Remotes)
local DataManager       = require(script.Parent.DataManager)
local PlotManager       = require(script.Parent.PlotManager)

local FarmManager = {}

-- farmData[plotId] = { level, hp, maxHp, model, alive }
local farmData = {}

local function buildFarmModel(plotId, level)
	local plot = PlotManager.GetPlot(plotId)
	if not plot then return end

	-- Убираем старую модель если есть
	local old = plot.folder:FindFirstChild("Farm")
	if old then old:Destroy() end

	local center = plot.center

	local farmFolder = Instance.new("Folder")
	farmFolder.Name   = "Farm"
	farmFolder.Parent = plot.folder

	-- Основание фермы
	local base = Instance.new("Part")
	base.Name     = "Base"
	base.Anchored = true
	base.Size     = Vector3.new(14, 1, 14)
	base.Position = center + Vector3.new(0, 1.5, -10)
	base.Color    = Config.FARM_COLOR[level]
	base.Material = Enum.Material.SmoothPlastic
	base.Parent   = farmFolder

	-- Корпус здания
	local body = Instance.new("Part")
	body.Name     = "Body"
	body.Anchored = true
	body.Size     = Vector3.new(10, 8+ level * 2, 10)
	body.Position = center + Vector3.new(0, 5+ level, -10)
	body.Color    = Config.FARM_COLOR[level]
	body.Material = Enum.Material.SmoothPlastic
	body.Parent   = farmFolder

	-- Крыша
	local roof = Instance.new("Part")
	roof.Name     = "Roof"
	roof.Anchored = true
	roof.Shape    = Enum.PartType.Wedge
	roof.Size     = Vector3.new(12, 4, 12)
	roof.Position = center + Vector3.new(0, 10+ level * 2, -10)
	roof.Color    = Config.FARM_COLOR[level]:Lerp(Color3.fromRGB(40,40,40), 0.3)
	roof.Material = Enum.Material.SmoothPlastic
	roof.Parent   = farmFolder

	-- HP BillboardGui над зданием
	local hpGui = Instance.new("BillboardGui")
	hpGui.Name= "HpGui"
	hpGui.Size          = UDim2.new(0, 160, 0, 30)
	hpGui.StudsOffset   = Vector3.new(0, 14+ level * 2, 0)
	hpGui.AlwaysOnTop   = false
	hpGui.Parent        = body

	local hpBar = Instance.new("Frame")
	hpBar.Name= "Bar"
	hpBar.Size            = UDim2.new(1, 0, 1, 0)
	hpBar.BackgroundColor3 = Color3.fromRGB(60, 200, 60)
	hpBar.BorderSizePixel = 0
	hpBar.Parent          = hpGui

	local hpBg = Instance.new("Frame")
	hpBg.Name            = "Bg"
	hpBg.Size            = UDim2.new(1, 0, 1, 0)
	hpBg.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
	hpBg.ZIndex          = 0
	hpBg.BorderSizePixel = 0
	hpBg.Parent          = hpGui

	hpBar.ZIndex = 1

	-- Уровень
	local lvlLabel = Instance.new("TextLabel")
	lvlLabel.Size            = UDim2.new(0, 160, 0, 24)
	lvlLabel.Position        = UDim2.new(0, 0, -1, 0)
	lvlLabel.BackgroundTransparency = 1
	lvlLabel.Text            = "Ур. " .. level
	lvlLabel.TextColor3      = Color3.fromRGB(255, 220, 50)
	lvlLabel.TextScaled      = true
	lvlLabel.Font            = Enum.Font.GothamBold
	lvlLabel.Parent          = hpGui

	return farmFolder, body
end

local function updateHpBar(plotId)
	local fd = farmData[plotId]
	if not fd or not fd.body then return end
	local hpGui = fd.body:FindFirstChild("HpGui")
	if not hpGui then return end
	local bar = hpGui:FindFirstChild("Bar")
	if bar then
		bar.Size = UDim2.new(math.clamp(fd.hp / fd.maxHp, 0, 1), 0, 1, 0)
	end
end

local function spawnFarm(plotId, level)
	level = level or 1
	local maxHp = Config.FARM_HP[level]
	local folder, body = buildFarmModel(plotId, level)
	farmData[plotId] = {
		level  = level,
		hp     = maxHp,
		maxHp  = maxHp,
		folder = folder,
		body   = body,
		alive  = true,
	}
end

local function destroyFarm(plotId)
	local fd = farmData[plotId]
	if not fd then return end
	fd.alive = false

	-- Визуально — красим в серый "мусор"
	if fd.folder then
		for _, part in ipairs(fd.folder:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Color= Color3.fromRGB(80, 80, 80)
				part.Material = Enum.Material.Concrete
			end
		end
	end

	-- Сообщаем всем клиентам
	Remotes.Get("FarmDestroyed"):FireAllClients(plotId)

	-- Восстанавливаем через FARM_REBUILD_TIME секунд
	task.delay(Config.FARM_REBUILD_TIME, function()
		local plot = PlotManager.GetPlot(plotId)
		if plot and plot.owner then
			local level = fd.level
			spawnFarm(plotId, level)
			Remotes.Get("FarmRebuilt"):FireAllClients(plotId)
		end
	end)
end

function FarmManager.Init()
	--Ферма создаётся когда игрок получает участок
	Players.PlayerAdded:Connect(function(player)
		task.wait(2)
		local plotId = select(1, PlotManager.GetPlotByPlayer(player))
		if plotId then
			spawnFarm(plotId, 1)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local plotId = select(1, PlotManager.GetPlotByPlayer(player))
		if plotId and farmData[plotId] then
			if farmData[plotId].folder then
				farmData[plotId].folder:Destroy()
			end
			farmData[plotId] = nil
		end
	end)

	-- Апгрейд фермы
	local upgradeEvent = Remotes.Get("UpgradeFarm")
	upgradeEvent.OnServerEvent:Connect(function(player)
		local plotId, _ = PlotManager.GetPlotByPlayer(player)
		if not plotId then return end
		local fd = farmData[plotId]
		if not fd or not fd.alive then return end
		local nextLevel = fd.level + 1
		if nextLevel > Config.MAX_FARM_LEVEL then return end
		local cost = Config.UPGRADE_COST[nextLevel]
		local data = DataManager.GetData(player)
		if not data or data.money < cost then return end
		DataManager.AddMoney(player, -cost)
		spawnFarm(plotId, nextLevel)
	end)

	-- Тик фарма — каждые FARM_INTERVAL секунд
	task.spawn(function()
		while true do
			task.wait(Config.FARM_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				local plotId = select(1, PlotManager.GetPlotByPlayer(player))
				if plotId then
					local fd = farmData[plotId]
					if fd and fd.alive then
						local income = Config.FARM_INCOME[fd.level] or 50
						DataManager.AddMoney(player, income)
					end
				end
			end
		end
	end)
end

function FarmManager.DamageAtPlot(plotId, damage)
	local fd = farmData[plotId]
	if not fd or not fd.alive then return false end
	fd.hp = math.max(0, fd.hp - damage)
	updateHpBar(plotId)
	Remotes.Get("FarmHit"):FireAllClients(plotId, fd.hp, fd.maxHp)
	if fd.hp <= 0 then
		destroyFarm(plotId)
		return true  -- уничтожена
	end
	return false
end

function FarmManager.GetFarmCenter(plotId)
	local plot = PlotManager.GetPlot(plotId)
	if not plot then return Vector3.zero end
	return plot.center + Vector3.new(0, 8, -10)
end

return FarmManager