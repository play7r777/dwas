-- FarmManager.luau — Строительство зданий, логика доходов, получение урона и КД восстановления
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Config            = require(sharedFolder:WaitForChild("Config"))
local Remotes           = require(sharedFolder:WaitForChild("Remotes"))
local DataManager       = require(script.Parent:WaitForChild("DataManager"))
local PlotManager       = require(script.Parent:WaitForChild("PlotManager"))

local FarmManager = {}

-- plotFarms[plotId][slotIndex] = { tier, hp, maxHp, alive, rebuildTimer, folder, body, hpBar, statusLabel }
local plotFarms = {}

-- Генерация кусочка суши и моста при покупке слота
local function buildTerritory(plotId, slotIndex)
	local plot = PlotManager.GetPlot(plotId)
	local slotInfo = plot.slots[slotIndex]
	local center = slotInfo.center
	local edgePos = slotInfo.edgePos

	local territoryFolder = Instance.new("Folder")
	territoryFolder.Name = "Territory_" .. slotIndex
	territoryFolder.Parent = plot.folder

	local dist = (center - edgePos).Magnitude
	local shoreY = plot.center.Y + 10
	local bridgeStart = Vector3.new(edgePos.X, shoreY, edgePos.Z)
	local bridgeEnd = Vector3.new(center.X, shoreY, center.Z)

	local bridge = Instance.new("Part")
	bridge.Name = "Bridge"
	bridge.Anchored = true
	bridge.Size = Vector3.new(7, 1.2, dist)
	bridge.CFrame = CFrame.lookAt(bridgeStart, bridgeEnd) * CFrame.new(0, 0, -dist / 2)
	bridge.Color = Color3.fromRGB(115, 79, 43)
	bridge.Material = Enum.Material.WoodPlanks
	bridge.Parent = territoryFolder

	for supportIndex = 1, 3 do
		local fraction = supportIndex / 4
		local support = Instance.new("Part")
		support.Name = "BridgePost"
		support.Anchored = true
		support.Size = Vector3.new(1.2, 22, 1.2)
		support.Position = bridgeStart:Lerp(bridgeEnd, fraction) - Vector3.new(0, 11, 0)
		support.Color = Color3.fromRGB(73, 52, 34)
		support.Material = Enum.Material.Wood
		support.Parent = territoryFolder
	end

	local bottom = Instance.new("Part")
	bottom.Name = "RockBottom"
	bottom.Anchored = true
	bottom.Shape = Enum.PartType.Cylinder
	bottom.Size = Vector3.new(22, Config.SLOT_PLATFORM_SIZE * 0.9, Config.SLOT_PLATFORM_SIZE * 0.9)
	bottom.Orientation = Vector3.new(0, 0, 90)
	bottom.Position = center - Vector3.new(0, 2, 0)
	bottom.Color = Color3.fromRGB(81, 78, 69)
	bottom.Material = Enum.Material.Rock
	bottom.Parent = territoryFolder

	local top = Instance.new("Part")
	top.Name = "IslandTop"
	top.Anchored = true
	top.Shape = Enum.PartType.Cylinder
	top.Size = Vector3.new(7, Config.SLOT_PLATFORM_SIZE, Config.SLOT_PLATFORM_SIZE)
	top.Orientation = Vector3.new(0, 0, 90)
	top.Position = center + Vector3.new(0, 6, 0)
	top.Color = Color3.fromRGB(235, 211, 149)
	top.Material = Enum.Material.Sand
	top.Parent = territoryFolder

	return territoryFolder
end

-- Уникальные 3D модели зданий
local function buildBuildingModel(plotId, slotIndex, tier, territoryFolder)
	local plot = PlotManager.GetPlot(plotId)
	local center = plot.slots[slotIndex].center + Vector3.new(0, 10, 0)
	local config = Config.FARM_TYPES[tier]
	local home = Instance.new("Model")
	home.Name = "IncomeHome_" .. slotIndex
	home:SetAttribute("Alive", true)
	home.Parent = territoryFolder

	local palettes = {
		{ wall = Color3.fromRGB(244, 226, 192), roof = Color3.fromRGB(174, 70, 50), trim = Color3.fromRGB(115, 76, 48) },
		{ wall = Color3.fromRGB(219, 231, 222), roof = Color3.fromRGB(67, 105, 119), trim = Color3.fromRGB(77, 67, 52) },
		{ wall = Color3.fromRGB(238, 221, 192), roof = Color3.fromRGB(107, 81, 151), trim = Color3.fromRGB(83, 60, 46) },
		{ wall = Color3.fromRGB(239, 232, 212), roof = Color3.fromRGB(190, 104, 43), trim = Color3.fromRGB(93, 60, 38) },
		{ wall = Color3.fromRGB(223, 224, 230), roof = Color3.fromRGB(67, 75, 92), trim = Color3.fromRGB(57, 52, 48) },
	}
	local palette = palettes[tier]
	local width = 16 + tier * 2
	local depth = 14 + tier * 2
	local wallHeight = 9 + tier

	local function part(name, size, cframe, color, material)
		local instance = Instance.new("Part")
		instance.Name = name
		instance.Anchored = true
		instance.Size = size
		instance.CFrame = cframe
		instance.Color = color
		instance.Material = material
		instance.TopSurface = Enum.SurfaceType.Smooth
		instance.BottomSurface = Enum.SurfaceType.Smooth
		instance.Parent = home
		return instance
	end

	local floor = part("Floor", Vector3.new(width, 1, depth), CFrame.new(center), Color3.fromRGB(126, 91, 54), Enum.Material.WoodPlanks)
	local wallY = center.Y + wallHeight / 2 + 0.5
	part("BackWall", Vector3.new(width, wallHeight, 1), CFrame.new(center + Vector3.new(0, wallY - center.Y, depth / 2)), palette.wall, Enum.Material.Plaster)
	part("LeftWall", Vector3.new(1, wallHeight, depth), CFrame.new(center + Vector3.new(-width / 2, wallY - center.Y, 0)), palette.wall, Enum.Material.Plaster)
	part("RightWall", Vector3.new(1, wallHeight, depth), CFrame.new(center + Vector3.new(width / 2, wallY - center.Y, 0)), palette.wall, Enum.Material.Plaster)

	-- The front is split around a real door opening, so players can walk inside.
	local sideWidth = (width - 5) / 2
	part("FrontWallLeft", Vector3.new(sideWidth, wallHeight, 1), CFrame.new(center + Vector3.new(-(5 + sideWidth) / 2, wallY - center.Y, -depth / 2)), palette.wall, Enum.Material.Plaster)
	part("FrontWallRight", Vector3.new(sideWidth, wallHeight, 1), CFrame.new(center + Vector3.new((5 + sideWidth) / 2, wallY - center.Y, -depth / 2)), palette.wall, Enum.Material.Plaster)
	part("DoorHeader", Vector3.new(5, 2.4, 1), CFrame.new(center + Vector3.new(0, wallHeight - 0.7, -depth / 2)), palette.trim, Enum.Material.Wood)

	local roofY = center.Y + wallHeight + 2
	local roofLeft = part("RoofLeft", Vector3.new(width / 2 + 1, 1, depth + 2), CFrame.new(center + Vector3.new(-width / 4, roofY, 0)) * CFrame.Angles(0, 0, math.rad(-24)), palette.roof, Enum.Material.Slate)
	local roofRight = part("RoofRight", Vector3.new(width / 2 + 1, 1, depth + 2), CFrame.new(center + Vector3.new(width / 4, roofY, 0)) * CFrame.Angles(0, 0, math.rad(24)), palette.roof, Enum.Material.Slate)
	part("Chimney", Vector3.new(2.2, 7, 2.2), CFrame.new(center + Vector3.new(width * 0.27, roofY + 3, 2)), Color3.fromRGB(92, 80, 71), Enum.Material.Brick)

	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -depth * 0.22, depth * 0.22 }) do
			local window = part("Window", Vector3.new(0.25, 3.2, 3.4), CFrame.new(center + Vector3.new(side * (width / 2 + 0.52), wallY, z)), Color3.fromRGB(133, 210, 226), Enum.Material.Glass)
			window.Transparency = 0.25
		end
	end

	local porch = part("Porch", Vector3.new(7, 0.7, 5), CFrame.new(center + Vector3.new(0, 0.25, -depth / 2 - 2.5)), Color3.fromRGB(128, 89, 50), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -2.8, 2.8 }) do
		part("PorchPost", Vector3.new(0.7, 5, 0.7), CFrame.new(center + Vector3.new(x, 2.7, -depth / 2 - 4.3)), palette.trim, Enum.Material.Wood)
	end
	part("PorchRoof", Vector3.new(8, 0.7, 3), CFrame.new(center + Vector3.new(0, 5.4, -depth / 2 - 3.2)) * CFrame.Angles(math.rad(8), 0, 0), palette.roof, Enum.Material.Slate)

	if tier >= 3 then
		part("SideRoom", Vector3.new(7, 7, 7), CFrame.new(center + Vector3.new(width / 2 + 3.5, 4, depth * 0.18)), palette.wall, Enum.Material.Plaster)
		part("SideRoof", Vector3.new(9, 1, 9), CFrame.new(center + Vector3.new(width / 2 + 3.5, 8.5, depth * 0.18)) * CFrame.Angles(0, 0, math.rad(18)), palette.roof, Enum.Material.Slate)
	end
	if tier >= 4 then
		local balcony = part("Balcony", Vector3.new(7, 0.6, 4), CFrame.new(center + Vector3.new(0, wallHeight * 0.63, depth / 2 + 2)), palette.trim, Enum.Material.WoodPlanks)
		balcony.CanCollide = true
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "StatusGui"
	gui.Size = UDim2.new(0, 130, 0, 28)
	gui.StudsOffset = Vector3.new(0, wallHeight + 5, 0)
	gui.AlwaysOnTop = false
	gui.Parent = roofLeft
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, 0, 1, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "+$" .. config.income
	statusLabel.TextColor3 = Color3.fromRGB(129, 255, 161)
	statusLabel.TextStrokeTransparency = 0.55
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Parent = gui

	return home, roofLeft, nil, statusLabel
end

local function buildLegacyBuildingModel(plotId, slotIndex, tier, territoryFolder)
	local plot = PlotManager.GetPlot(plotId)
	local slotInfo = plot.slots[slotIndex]
	local center = slotInfo.center
	local farmConfig = Config.FARM_TYPES[tier]

	local farmFolder = Instance.new("Folder")
	farmFolder.Name = "FarmSlot_" .. slotIndex
	farmFolder:SetAttribute("Alive", true)
	farmFolder.Parent = territoryFolder

	local mainBody -- Центральная часть для Gui

	-- База для всех зданий
	local base = Instance.new("Part")
	base.Anchored = true
	base.Size = Vector3.new(16, 1, 16)
	base.Position = center + Vector3.new(0, 2.5, 0)
	base.Color = Color3.fromRGB(40, 40, 45)
	base.Material = Enum.Material.DiamondPlate
	base.Parent = farmFolder
	mainBody = base

	local heightOffset = 3

	if tier == 1 then
		-- Солнечная ферма
		local pillar = Instance.new("Part")
		pillar.Anchored = true
		pillar.Size = Vector3.new(2, 8, 2)
		pillar.Position = base.Position + Vector3.new(0, 4, 0)
		pillar.Color = Color3.fromRGB(150, 150, 150)
		pillar.Parent = farmFolder

		local panel = Instance.new("Part")
		panel.Anchored = true
		panel.Size = Vector3.new(12, 0.5, 12)
		panel.CFrame = CFrame.new(pillar.Position + Vector3.new(0, 4, 0)) * CFrame.Angles(math.rad(30), 0, 0)
		panel.Color = farmConfig.color
		panel.Material = farmConfig.material
		panel.Parent = farmFolder
		mainBody = panel
		heightOffset = 5

	elseif tier == 2 then
		-- Кристальная шахта
		mainBody = Instance.new("Part")
		mainBody.Anchored = true
		mainBody.Size = Vector3.new(10, 6, 10)
		mainBody.Position = base.Position + Vector3.new(0, 3, 0)
		mainBody.Color = Color3.fromRGB(60, 50, 60)
		mainBody.Material = Enum.Material.Slate
		mainBody.Parent = farmFolder

		for i = 1, 4 do
			local crystal = Instance.new("Part")
			crystal.Anchored = true
			crystal.Shape = Enum.PartType.Ball
			crystal.Size = Vector3.new(4, 12, 4)
			crystal.CFrame = CFrame.new(mainBody.Position + Vector3.new(0, 4, 0)) * CFrame.Angles(math.rad(math.random(-30, 30)), math.rad(i * 90), math.rad(30))
			crystal.Color = farmConfig.color
			crystal.Material = Enum.Material.Neon
			crystal.Parent = farmFolder
		end
		heightOffset = 10

	elseif tier == 3 then
		-- Био-Лаборатория
		mainBody = Instance.new("Part")
		mainBody.Anchored = true
		mainBody.Shape = Enum.PartType.Cylinder
		mainBody.Size = Vector3.new(10, 14, 14)
		mainBody.Orientation = Vector3.new(0, 0, 90)
		mainBody.Position = base.Position + Vector3.new(0, 5, 0)
		mainBody.Color = Color3.fromRGB(150, 150, 150)
		mainBody.Material = Enum.Material.Metal
		mainBody.Parent = farmFolder

		local dome = Instance.new("Part")
		dome.Anchored = true
		dome.Shape = Enum.PartType.Ball
		dome.Size = Vector3.new(12, 12, 12)
		dome.Position = mainBody.Position + Vector3.new(0, 2, 0)
		dome.Color = Color3.fromRGB(200, 255, 200)
		dome.Material = Enum.Material.Glass
		dome.Transparency = 0.5
		dome.Parent = farmFolder

		local fluid = Instance.new("Part")
		fluid.Anchored = true
		fluid.Shape = Enum.PartType.Ball
		fluid.Size = Vector3.new(8, 8, 8)
		fluid.Position = dome.Position
		fluid.Color = farmConfig.color
		fluid.Material = Enum.Material.Neon
		fluid.Parent = farmFolder
		heightOffset = 9

	elseif tier == 4 then
		-- Плазменный генератор
		mainBody = Instance.new("Part")
		mainBody.Anchored = true
		mainBody.Shape = Enum.PartType.Cylinder
		mainBody.Size = Vector3.new(12, 8, 8)
		mainBody.Orientation = Vector3.new(0, 0, 90)
		mainBody.Position = base.Position + Vector3.new(0, 6, 0)
		mainBody.Color = Color3.fromRGB(40, 40, 40)
		mainBody.Material = Enum.Material.Metal
		mainBody.Parent = farmFolder

		local orb = Instance.new("Part")
		orb.Anchored = true
		orb.Shape = Enum.PartType.Ball
		orb.Size = Vector3.new(8, 8, 8)
		orb.Position = mainBody.Position + Vector3.new(0, 8, 0)
		orb.Color = farmConfig.color
		orb.Material = Enum.Material.Neon
		orb.Parent = farmFolder
		heightOffset = 18

	elseif tier == 5 then
		-- Квантовый реактор
		mainBody = Instance.new("Part")
		mainBody.Anchored = true
		mainBody.Size = Vector3.new(10, 16, 10)
		mainBody.Position = base.Position + Vector3.new(0, 8, 0)
		mainBody.Color = Color3.fromRGB(20, 20, 20)
		mainBody.Material = Enum.Material.Metal
		mainBody.Parent = farmFolder

		local ring = Instance.new("Part")
		ring.Anchored = true
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(4, 20, 20)
		ring.Orientation = Vector3.new(45, 45, 90)
		ring.Position = mainBody.Position
		ring.Color = farmConfig.color
		ring.Material = Enum.Material.Neon
		ring.CanCollide = false
		ring.Parent = farmFolder

		local core = Instance.new("Part")
		core.Anchored = true
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.new(10, 10, 10)
		core.Position = mainBody.Position
		core.Color = farmConfig.color
		core.Material = Enum.Material.ForceField
		core.Parent = farmFolder
		heightOffset = 12
	end

	-- 3D Информационная панель над зданием
	local gui = Instance.new("BillboardGui")
	gui.Name = "StatusGui"
	gui.Size = UDim2.new(0, 180, 0, 50)
	gui.StudsOffset = Vector3.new(0, heightOffset, 0)
	gui.AlwaysOnTop = false
	gui.Parent = mainBody

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = string.format("%s (Тир %d)", farmConfig.name, tier)
	nameLabel.TextColor3 = Color3.fromRGB(255, 220, 50)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = gui

	local hpBg = Instance.new("Frame")
	hpBg.Name = "HpBg"
	hpBg.Size = UDim2.new(1, 0, 0, 12)
	hpBg.Position = UDim2.new(0, 0, 0, 20)
	hpBg.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
	hpBg.BorderSizePixel = 0
	hpBg.Parent = gui

	local hpBar = Instance.new("Frame")
	hpBar.Name = "HpBar"
	hpBar.Size = UDim2.new(1, 0, 1, 0)
	hpBar.BackgroundColor3 = Color3.fromRGB(50, 220, 50)
	hpBar.BorderSizePixel = 0
	hpBar.Parent = hpBg

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, 0, 0, 14)
	statusLabel.Position = UDim2.new(0, 0, 0, 34)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = "+$" .. farmConfig.income
	statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.GothamMedium
	statusLabel.Parent = gui

	return farmFolder, mainBody, hpBar, statusLabel
end

local function spawnBuilding(plotId, slotIndex, tier)
	if not plotFarms[plotId] then plotFarms[plotId] = {} end

	local oldData = plotFarms[plotId][slotIndex]
	if oldData and oldData.folder then
		oldData.folder:Destroy()
	end

	local plot = PlotManager.GetPlot(plotId)

	-- Если территории еще нет, строим её
	local territoryFolder = plot.folder:FindFirstChild("Territory_" .. slotIndex)
	if not territoryFolder then
		territoryFolder = buildTerritory(plotId, slotIndex)
	end

	local farmConfig = Config.FARM_TYPES[tier]
	local folder, body, hpBar, statusLabel = buildBuildingModel(plotId, slotIndex, tier, territoryFolder)

	if plot and plot.slots[slotIndex] then
		plot.slots[slotIndex].buyPad.Transparency = 1
		plot.slots[slotIndex].buyPad.CanCollide = false
		plot.slots[slotIndex].buyPrompt.Enabled = false
	end

	-- Активация кнопки СЛЕДУЮЩЕГО слота (последовательная прокачка)
	local nextSlot = slotIndex + 1
	if plot and plot.slots[nextSlot] and not (plotFarms[plotId] and plotFarms[plotId][nextSlot]) then
		plot.slots[nextSlot].buyPad.Transparency = 0
		plot.slots[nextSlot].buyPad.CanCollide = true
		plot.slots[nextSlot].buyPrompt.Enabled = true
	end

	plotFarms[plotId][slotIndex] = {
		tier = tier,
		hp = farmConfig.maxHp,
		maxHp = farmConfig.maxHp,
		alive = true,
		folder = folder,
		body = body,
		hpBar = hpBar,
		statusLabel = statusLabel,
		rebuildTimer = 0,
	}

	Remotes.Get("BuildingStateChanged"):FireAllClients(plotId, slotIndex, {
		tier = tier,
		hp = farmConfig.maxHp,
		maxHp = farmConfig.maxHp,
		alive = true,
		rebuildTimer = 0,
	})
end

function FarmManager.BuySlot(player, slotIndex)
	local plotId = select(1, PlotManager.GetPlotByPlayer(player))
	if not plotId then return end

	-- Проверка последовательности прокачки: можно купить слот N, только если есть слот N-1
	if slotIndex > 1 and (not plotFarms[plotId] or not plotFarms[plotId][slotIndex - 1]) then
		return
	end

	local farmConfig = Config.FARM_TYPES[slotIndex]
	if not farmConfig then return end

	local currentData = plotFarms[plotId] and plotFarms[plotId][slotIndex]
	if currentData then return end

	local playerMoney = DataManager.GetMoney(player)
	if playerMoney >= farmConfig.cost then
		DataManager.AddMoney(player, -farmConfig.cost)
		spawnBuilding(plotId, slotIndex, slotIndex)
		print(string.format("[FarmManager] %s открыл новую территорию и построил %s!", player.Name, farmConfig.name))
	end
end

local function destroyBuilding(plotId, slotIndex)
	local slotData = plotFarms[plotId] and plotFarms[plotId][slotIndex]
	if not slotData or not slotData.alive then return end

	slotData.alive = false
	if slotData.folder then slotData.folder:SetAttribute("Alive", false) end
	local farmConfig = Config.FARM_TYPES[slotData.tier]
	local cd = farmConfig.cooldown

	if slotData.folder then
		for _, part in ipairs(slotData.folder:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Color = Color3.fromRGB(60, 60, 65)
				part.Material = Enum.Material.Concrete
			end
		end
	end

	if slotData.hpBar then slotData.hpBar.Size = UDim2.new(0, 0, 1, 0) end

	task.spawn(function()
		for timeLeft = cd, 1, -1 do
			if not slotData or slotData.alive then break end
			slotData.rebuildTimer = timeLeft
			if slotData.statusLabel then
				slotData.statusLabel.Text = string.format("Ремонт %dс", timeLeft)
				slotData.statusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
			end

			Remotes.Get("BuildingStateChanged"):FireAllClients(plotId, slotIndex, {
				tier = slotData.tier,
				hp = 0,
				maxHp = slotData.maxHp,
				alive = false,
				rebuildTimer = timeLeft,
			})
			task.wait(1)
		end

		local plot = PlotManager.GetPlot(plotId)
		if plot and plot.owner then
			spawnBuilding(plotId, slotIndex, slotData.tier)
			print(string.format("[FarmManager] Остров #%d Слот #%d заново восстановлен!", plotId, slotIndex))
		end
	end)
end

function FarmManager.Init()
	for plotId, plot in pairs(PlotManager.GetAllPlots()) do
		for slotIdx, slotInfo in ipairs(plot.slots) do
			slotInfo.buyPad.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if player and plot.owner == player then
					FarmManager.BuySlot(player, slotIdx)
				end
			end)
			slotInfo.buyPrompt.Triggered:Connect(function(player)
				if plot.owner == player then
					FarmManager.BuySlot(player, slotIdx)
				end
			end)
		end
	end

	local buyEvent = Remotes.Get("BuyBuildingSlot")
	buyEvent.OnServerEvent:Connect(function(player, slotIndex)
		if type(slotIndex) == "number" then
			FarmManager.BuySlot(player, slotIndex)
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.wait(1.5)
		local plotId = select(1, PlotManager.GetPlotByPlayer(player))
		if plotId then
			if not plotFarms[plotId] then plotFarms[plotId] = {} end

			-- Делаем кнопку первого слота видимой
			local plot = PlotManager.GetPlot(plotId)
			if plot and plot.slots[1] then
				plot.slots[1].buyPad.Transparency = 0
				plot.slots[1].buyPad.CanCollide = true
				plot.slots[1].buyPrompt.Enabled = true
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local plotId = player:GetAttribute("PlotId") or select(1, PlotManager.GetPlotByPlayer(player))
		if plotId and plotFarms[plotId] then
			for _, slotData in pairs(plotFarms[plotId]) do
				if slotData.folder then slotData.folder:Destroy() end
			end
			plotFarms[plotId] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.FARM_INTERVAL)
			for _, player in ipairs(Players:GetPlayers()) do
				local plotId = select(1, PlotManager.GetPlotByPlayer(player))
				if plotId and plotFarms[plotId] then
					for slotIdx, slotData in pairs(plotFarms[plotId]) do
						if slotData and slotData.alive then
							local farmConfig = Config.FARM_TYPES[slotData.tier]
							if farmConfig then
								DataManager.AddMoney(player, farmConfig.income)
								local plot = PlotManager.GetPlot(plotId)
								if plot and plot.slots[slotIdx] then
									Remotes.Get("SpawnIncomeFX"):FireClient(player, plot.slots[slotIdx].center + Vector3.new(0, 10, 0), farmConfig.income)
								end
							end
						end
					end
				end
			end
		end
	end)
end

function FarmManager.GetSlotTargetPosition(plotId, slotIndex)
	local plot = PlotManager.GetPlot(plotId)
	if not plot or not plot.slots[slotIndex] then
		return plot and plot.center or Vector3.zero
	end
	return plot.slots[slotIndex].center + Vector3.new(0, 6, 0)
end

function FarmManager.IsSlotAlive(plotId, slotIndex)
	local slotData = plotFarms[plotId] and plotFarms[plotId][slotIndex]
	return slotData ~= nil and slotData.alive == true
end

function FarmManager.DamageAtSlot(plotId, slotIndex, damage)
	local slotData = plotFarms[plotId] and plotFarms[plotId][slotIndex]
	if not slotData or not slotData.alive then return false end

	slotData.hp = math.max(0, slotData.hp - damage)
	if slotData.hpBar then
		slotData.hpBar.Size = UDim2.new(math.clamp(slotData.hp / slotData.maxHp, 0, 1), 0, 1, 0)
	end

	if slotData.hp <= 0 then
		destroyBuilding(plotId, slotIndex)
		return true
	end
	return false
end

function FarmManager.GetAllFarmData()
	return plotFarms
end

return FarmManager