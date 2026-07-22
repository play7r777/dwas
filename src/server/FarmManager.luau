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

-- Уникальные 3D модели зданий. baseCF ставит дом фасадом (входом) к центру острова,
-- чтобы дом не стоял "задом" к своему острову (фикс ориентации красного дома).
local function buildBuildingModel(plotId, slotIndex, tier, level, territoryFolder)
	local plot = PlotManager.GetPlot(plotId)
	local slotCenter = plot.slots[slotIndex].center + Vector3.new(0, 10, 0)
	-- Дверь/фасад дома смотрит по локальной -Z; направляем -Z на центр острова (к мосту).
	local baseCF = CFrame.lookAt(slotCenter, Vector3.new(plot.center.X, slotCenter.Y, plot.center.Z))

	local config = Config.FARM_TYPES[tier]
	local income = Config.IncomeForLevel(tier, level)
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

	-- lp — все смещения ЛОКАЛЬНЫЕ относительно пола дома (baseCF), пол на локальном y=0.
	local function lp(name, size, dx, dy, dz, color, material, angles)
		local cf = baseCF * CFrame.new(dx, dy, dz)
		if angles then cf = cf * angles end
		local instance = Instance.new("Part")
		instance.Name = name
		instance.Anchored = true
		instance.Size = size
		instance.CFrame = cf
		instance.Color = color
		instance.Material = material
		instance.TopSurface = Enum.SurfaceType.Smooth
		instance.BottomSurface = Enum.SurfaceType.Smooth
		instance.Parent = home
		return instance
	end

	local wallY = wallHeight / 2 + 0.5   -- ЛОКАЛЬНАЯ высота центра стен
	local roofY = wallHeight + 2          -- ЛОКАЛЬНАЯ высота конька крыши (сидит на стенах)

	lp("Floor", Vector3.new(width, 1, depth), 0, 0, 0, Color3.fromRGB(126, 91, 54), Enum.Material.WoodPlanks)
	lp("BackWall", Vector3.new(width, wallHeight, 1), 0, wallY, depth / 2, palette.wall, Enum.Material.Plaster)
	lp("LeftWall", Vector3.new(1, wallHeight, depth), -width / 2, wallY, 0, palette.wall, Enum.Material.Plaster)
	lp("RightWall", Vector3.new(1, wallHeight, depth), width / 2, wallY, 0, palette.wall, Enum.Material.Plaster)

	-- Фасад со сквозным дверным проёмом.
	local sideWidth = (width - 5) / 2
	lp("FrontWallLeft", Vector3.new(sideWidth, wallHeight, 1), -(5 + sideWidth) / 2, wallY, -depth / 2, palette.wall, Enum.Material.Plaster)
	lp("FrontWallRight", Vector3.new(sideWidth, wallHeight, 1), (5 + sideWidth) / 2, wallY, -depth / 2, palette.wall, Enum.Material.Plaster)
	lp("DoorHeader", Vector3.new(5, 2.4, 1), 0, wallHeight - 0.7, -depth / 2, palette.trim, Enum.Material.Wood)

	-- Двускатная крыша должна образовывать КОНЁК (пик /\), а не ложбину (\/):
	-- у обоих скатов внутренний край (к центру дома) выше внешнего. Раньше знаки
	-- наклона были перевёрнуты — главный скат выглядел как "\" вместо "/".
	local roofLeft = lp("RoofLeft", Vector3.new(width / 2 + 1, 1, depth + 2), -width / 4, roofY, 0, palette.roof, Enum.Material.Slate, CFrame.Angles(0, 0, math.rad(24)))
	lp("RoofRight", Vector3.new(width / 2 + 1, 1, depth + 2), width / 4, roofY, 0, palette.roof, Enum.Material.Slate, CFrame.Angles(0, 0, math.rad(-24)))
	lp("Chimney", Vector3.new(2.2, 7, 2.2), width * 0.27, roofY + 3, 2, Color3.fromRGB(92, 80, 71), Enum.Material.Brick)

	for _, side in ipairs({ -1, 1 }) do
		for _, z in ipairs({ -depth * 0.22, depth * 0.22 }) do
			local window = lp("Window", Vector3.new(0.25, 3.2, 3.4), side * (width / 2 + 0.52), wallY, z, Color3.fromRGB(133, 210, 226), Enum.Material.Glass)
			window.Transparency = 0.25
		end
	end

	lp("Porch", Vector3.new(7, 0.7, 5), 0, 0.25, -depth / 2 - 2.5, Color3.fromRGB(128, 89, 50), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -2.8, 2.8 }) do
		lp("PorchPost", Vector3.new(0.7, 5, 0.7), x, 2.7, -depth / 2 - 4.3, palette.trim, Enum.Material.Wood)
	end
	lp("PorchRoof", Vector3.new(8, 0.7, 3), 0, 5.4, -depth / 2 - 3.2, palette.roof, Enum.Material.Slate, CFrame.Angles(math.rad(8), 0, 0))

	if tier >= 3 then
		lp("SideRoom", Vector3.new(7, 7, 7), width / 2 + 3.5, 4, depth * 0.18, palette.wall, Enum.Material.Plaster)
		-- Малый скат пристройки тоже был перевёрнут ("\"); разворачиваем в "/".
		lp("SideRoof", Vector3.new(9, 1, 9), width / 2 + 3.5, 8.5, depth * 0.18, palette.roof, Enum.Material.Slate, CFrame.Angles(0, 0, math.rad(-18)))
	end
	if tier >= 4 then
		local balcony = lp("Balcony", Vector3.new(7, 0.6, 4), 0, wallHeight * 0.63, depth / 2 + 2, palette.trim, Enum.Material.WoodPlanks)
		balcony.CanCollide = true
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "StatusGui"
	gui.Size = UDim2.new(0, 150, 0, 30)
	gui.StudsOffset = Vector3.new(0, wallHeight + 5, 0)
	gui.AlwaysOnTop = false
	gui.Parent = roofLeft
	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, 0, 1, 0)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = string.format("ур.%d  +$%d", level, income)
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

-- Обновляет ценник над кнопкой: покупка / прокачка до след. уровня / макс.
local function updatePriceTag(plotId, slotIndex)
	local plot = PlotManager.GetPlot(plotId)
	local slot = plot and plot.slots[slotIndex]
	if not slot or not slot.priceLabel then return end
	local base = Config.FARM_TYPES[slotIndex]
	local data = plotFarms[plotId] and plotFarms[plotId][slotIndex]

	if not data then
		slot.priceLabel.Text = string.format("%s\n$%d", base.name, base.cost)
		slot.priceLabel.TextColor3 = Color3.fromRGB(240, 244, 246)
	elseif data.level >= Config.MAX_BUILDING_LEVEL then
		slot.priceLabel.Text = string.format("%s (ур.%d)\nМакс. уровень", base.name, data.level)
		slot.priceLabel.TextColor3 = Color3.fromRGB(255, 224, 150)
	else
		local cost = Config.UpgradeCost(slotIndex, data.level + 1)
		slot.priceLabel.Text = string.format("Прокачка до ур.%d\n$%d", data.level + 1, cost)
		slot.priceLabel.TextColor3 = Color3.fromRGB(240, 244, 246)
	end
end

-- Прочность здания растёт с уровнем.
local function maxHpForLevel(tier, level)
	local base = Config.FARM_TYPES[tier]
	return math.floor(base.maxHp * (1 + 0.35 * (level - 1)))
end

local function spawnBuilding(plotId, slotIndex, level)
	if not plotFarms[plotId] then plotFarms[plotId] = {} end

	local oldData = plotFarms[plotId][slotIndex]
	if oldData and oldData.folder then
		oldData.folder:Destroy()
	end

	local plot = PlotManager.GetPlot(plotId)
	local tier = slotIndex -- слот N соответствует зданию тира N

	-- Если территории еще нет, строим её
	local territoryFolder = plot.folder:FindFirstChild("Territory_" .. slotIndex)
	if not territoryFolder then
		territoryFolder = buildTerritory(plotId, slotIndex)
	end

	local maxHp = maxHpForLevel(tier, level)
	local folder, body, hpBar, statusLabel = buildBuildingModel(plotId, slotIndex, tier, level, territoryFolder)

	-- Кнопка НЕ исчезает — она остаётся кнопкой прокачки этого здания.
	updatePriceTag(plotId, slotIndex)

	-- Активация кнопки СЛЕДУЮЩЕГО слота (последовательное открытие)
	local nextSlot = slotIndex + 1
	if plot and plot.slots[nextSlot] and not (plotFarms[plotId] and plotFarms[plotId][nextSlot]) then
		plot.slots[nextSlot].buyPad.Transparency = 0
		plot.slots[nextSlot].buyPad.CanCollide = true
		if plot.slots[nextSlot].billboard then plot.slots[nextSlot].billboard:SetAttribute("Unlocked", true) end
	end

	plotFarms[plotId][slotIndex] = {
		tier = tier,
		level = level,
		hp = maxHp,
		maxHp = maxHp,
		alive = true,
		folder = folder,
		body = body,
		hpBar = hpBar,
		statusLabel = statusLabel,
		rebuildTimer = 0,
	}

	Remotes.Get("BuildingStateChanged"):FireAllClients(plotId, slotIndex, {
		tier = tier,
		level = level,
		hp = maxHp,
		maxHp = maxHp,
		alive = true,
		rebuildTimer = 0,
	})
end

-- Наступание на кнопку: покупка (если пусто) или прокачка (если уже построено).
function FarmManager.BuyOrUpgrade(player, slotIndex)
	local plotId = select(1, PlotManager.GetPlotByPlayer(player))
	if not plotId then return end
	local base = Config.FARM_TYPES[slotIndex]
	if not base then return end
	if not plotFarms[plotId] then plotFarms[plotId] = {} end

	local data = plotFarms[plotId][slotIndex]
	if not data then
		-- ПОКУПКА (уровень 1). Слот N доступен, только если построен слот N-1.
		if slotIndex > 1 and not plotFarms[plotId][slotIndex - 1] then return end
		if DataManager.GetMoney(player) < base.cost then return end
		DataManager.AddMoney(player, -base.cost)
		spawnBuilding(plotId, slotIndex, 1)
		print(string.format("[FarmManager] %s построил %s (ур.1)", player.Name, base.name))
	else
		-- ПРОКАЧКА до следующего уровня.
		if not data.alive then return end
		if data.level >= Config.MAX_BUILDING_LEVEL then return end
		local nextLevel = data.level + 1
		local cost = Config.UpgradeCost(slotIndex, nextLevel)
		if DataManager.GetMoney(player) < cost then return end
		DataManager.AddMoney(player, -cost)
		spawnBuilding(plotId, slotIndex, nextLevel)
		print(string.format("[FarmManager] %s прокачал %s до ур.%d", player.Name, base.name, nextLevel))
	end
end

-- Совместимость со старым именем/ремоутом.
function FarmManager.BuySlot(player, slotIndex)
	FarmManager.BuyOrUpgrade(player, slotIndex)
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
			spawnBuilding(plotId, slotIndex, slotData.level or 1)
			print(string.format("[FarmManager] Остров #%d Слот #%d заново восстановлен!", plotId, slotIndex))
		end
	end)
end

local buyDebounce = {}

function FarmManager.Init()
	for plotId, plot in pairs(PlotManager.GetAllPlots()) do
		for slotIdx, slotInfo in ipairs(plot.slots) do
			-- Покупка/прокачка по НАСТУПАНИЮ на кнопку (с дебаунсом ~1с и проверкой владельца).
			slotInfo.buyPad.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if not player or plot.owner ~= player then return end
				local key = string.format("%d:%d:%d", player.UserId, plotId, slotIdx)
				local now = os.clock()
				if buyDebounce[key] and now - buyDebounce[key] < 1 then return end
				buyDebounce[key] = now
				FarmManager.BuyOrUpgrade(player, slotIdx)
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
				if plot.slots[1].billboard then plot.slots[1].billboard:SetAttribute("Unlocked", true) end
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
						local disabled = slotData and slotData.disabledUntil and workspace:GetServerTimeNow() < slotData.disabledUntil
						if slotData and slotData.alive and not disabled then
							local farmConfig = Config.FARM_TYPES[slotData.tier]
							if farmConfig then
								-- Доход растёт с уровнем здания.
								local income = Config.IncomeForLevel(slotData.tier, slotData.level or 1)
								DataManager.AddMoney(player, income)
								local plot = PlotManager.GetPlot(plotId)
								if plot and plot.slots[slotIdx] then
									Remotes.Get("SpawnIncomeFX"):FireClient(player, plot.slots[slotIdx].center + Vector3.new(0, 10, 0), income)
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

-- Ракетный прилёт «оглушает» здание: доход отключается на duration секунд,
-- здание темнеет и дымит, пока не восстановится. disabledUntil — серверная метка.
function FarmManager.DisableSlot(plotId, slotIndex, duration)
	local slotData = plotFarms[plotId] and plotFarms[plotId][slotIndex]
	if not slotData or not slotData.alive then return end

	slotData.disabledUntil = workspace:GetServerTimeNow() + duration

	-- Затемняем части здания, запомнив исходные цвет/материал для восстановления.
	if slotData.folder and not slotData.disabledParts then
		slotData.disabledParts = {}
		for _, part in ipairs(slotData.folder:GetDescendants()) do
			if part:IsA("BasePart") then
				table.insert(slotData.disabledParts, { part = part, color = part.Color, material = part.Material })
				part.Color = Color3.fromRGB(72, 66, 60)
				part.Material = Enum.Material.Concrete
			end
		end
	end

	-- Дым над зданием как признак повреждения.
	if slotData.body and not slotData.smoke then
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "DisabledSmoke"
		emitter.Texture = "rbxassetid://241594419"
		emitter.Color = ColorSequence.new(Color3.fromRGB(58, 58, 60))
		emitter.Size = NumberSequence.new(4, 9)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Lifetime = NumberRange.new(1.2, 2.2)
		emitter.Rate = 16
		emitter.Speed = NumberRange.new(4, 7)
		emitter.SpreadAngle = Vector2.new(22, 22)
		emitter.Acceleration = Vector3.new(0, 6, 0)
		emitter.Parent = slotData.body
		slotData.smoke = emitter
	end

	if slotData.statusLabel then
		slotData.statusLabel.Text = "Повреждено"
		slotData.statusLabel.TextColor3 = Color3.fromRGB(255, 120, 90)
	end

	Remotes.Get("BuildingStateChanged"):FireAllClients(plotId, slotIndex, {
		tier = slotData.tier,
		level = slotData.level,
		hp = slotData.hp,
		maxHp = slotData.maxHp,
		alive = slotData.alive,
		disabled = true,
		rebuildTimer = 0,
	})

	task.delay(duration, function()
		local cur = plotFarms[plotId] and plotFarms[plotId][slotIndex]
		if cur ~= slotData then return end -- здание было перестроено — старые данные не трогаем
		if not slotData.disabledUntil or workspace:GetServerTimeNow() < slotData.disabledUntil then return end
		slotData.disabledUntil = nil
		if slotData.disabledParts then
			for _, rec in ipairs(slotData.disabledParts) do
				if rec.part and rec.part.Parent then
					rec.part.Color = rec.color
					rec.part.Material = rec.material
				end
			end
			slotData.disabledParts = nil
		end
		if slotData.smoke then slotData.smoke:Destroy() slotData.smoke = nil end
		if slotData.statusLabel and slotData.alive then
			slotData.statusLabel.Text = string.format("ур.%d  +$%d", slotData.level or 1, Config.IncomeForLevel(slotData.tier, slotData.level or 1))
			slotData.statusLabel.TextColor3 = Color3.fromRGB(129, 255, 161)
		end
	end)
end

-- Серверный расчёт прилёта: находит здания в радиусе точки удара и наносит им
-- урон + отключает доход. Возвращает true, если что-то было разрушено.
function FarmManager.ApplyRocketImpact(plotId, impactPos, damage)
	local farms = plotFarms[plotId]
	local plot = PlotManager.GetPlot(plotId)
	if not farms or not plot then return false end

	local radius = Config.Rocket.ImpactRadius
	local anyDestroyed = false
	for slotIndex, slotData in pairs(farms) do
		if slotData and slotData.alive then
			local slot = plot.slots[slotIndex]
			if slot then
				local c = slot.center
				local flat = Vector3.new(c.X, impactPos.Y, c.Z)
				if (flat - impactPos).Magnitude <= radius then
					FarmManager.DisableSlot(plotId, slotIndex, Config.Rocket.DisableDuration)
					if FarmManager.DamageAtSlot(plotId, slotIndex, damage) then
						anyDestroyed = true
					end
				end
			end
		end
	end
	return anyDestroyed
end

function FarmManager.GetAllFarmData()
	return plotFarms
end

return FarmManager