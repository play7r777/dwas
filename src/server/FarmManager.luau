-- FarmManager.luau — Строительство зданий, логика доходов, получение урона и КД восстановления
--
-- v3: здания мини-городка полностью переработаны. Дом растёт ВВЕРХ с прокачкой
-- (уровень = количество этажей), у каждого тира свой архитектурный стиль, вокруг
-- дома — дорожка, фонари и кусты ("мини-городок" на каждой площадке).
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Config            = require(sharedFolder:WaitForChild("Config"))
local Remotes           = require(sharedFolder:WaitForChild("Remotes"))
local DataManager       = require(script.Parent:WaitForChild("DataManager"))
local PlotManager       = require(script.Parent:WaitForChild("PlotManager"))

local FarmManager = {}

-- plotFarms[plotId][slotIndex] = { tier, level, hp, maxHp, alive, rebuildTimer, folder, body, hpBar, statusLabel }
local plotFarms = {}

local function makeDecorPart(parent, name, size, cframe, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function makeDecorCylinder(parent, name, height, diameter, position, color, material)
	local part = makeDecorPart(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Генерация кусочка суши, моста и мини-городка при покупке слота
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
	top.Color = Color3.fromRGB(240, 202, 116) -- тёплый золотистый песок
	top.Material = Enum.Material.Sand
	top.Parent = territoryFolder

	-- === Мини-городок вокруг будущего дома: дорожка, фонари, кусты ===
	local up = Vector3.new(0, 1, 0)
	local toCenter = Vector3.new(plot.center.X - center.X, 0, plot.center.Z - center.Z)
	toCenter = toCenter.Magnitude > 0.001 and toCenter.Unit or Vector3.new(0, 0, -1)
	local side = toCenter:Cross(up)
	local sandTop = center.Y + 9.5 -- верх песчаного диска площадки
	local flatCenter = Vector3.new(center.X, sandTop, center.Z)

	-- Дорожка из плит от моста к крыльцу дома
	for i = 1, 3 do
		local r = Config.SLOT_PLATFORM_SIZE / 2 - 4 - (i - 1) * 6
		local tilePos = flatCenter + toCenter * r + Vector3.new(0, 0.15, 0)
		makeDecorPart(territoryFolder, "PathTile_" .. i, Vector3.new(3.6, 0.3, 4.4), CFrame.lookAt(tilePos, tilePos + toCenter), Color3.fromRGB(196, 186, 168), Enum.Material.Concrete)
	end

	-- Пара уличных фонарей у дорожки (тёплый свет вечером)
	for _, s in ipairs({ -1, 1 }) do
		local lampBase = flatCenter + toCenter * 19 + side * (s * 6)
		makeDecorCylinder(territoryFolder, "LampPole", 5.4, 0.5, lampBase + Vector3.new(0, 2.7, 0), Color3.fromRGB(52, 56, 62), Enum.Material.Metal)
		local bulb = makeDecorPart(territoryFolder, "LampBulb", Vector3.new(1.1, 1.1, 1.1), CFrame.new(lampBase + Vector3.new(0, 5.7, 0)), Color3.fromRGB(255, 214, 120), Enum.Material.Neon)
		bulb.Shape = Enum.PartType.Ball
		bulb.CanCollide = false
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 208, 120)
		light.Brightness = 0.9
		light.Range = 15
		light.Parent = bulb
	end

	-- Кусты вокруг дома (не залезают в стены: отступ от полуширины дома тира)
	local tier = slotIndex
	local halfWidth = (16 + tier * 2) / 2
	local bushOffsets = {
		side * (halfWidth + 2.5) + toCenter * 2,
		side * -(halfWidth + 2.5) + toCenter * 2,
		toCenter * -(halfWidth + 5) + side * 5,
	}
	for i, off in ipairs(bushOffsets) do
		local bush = makeDecorPart(territoryFolder, "Bush_" .. i, Vector3.new(3, 2.4, 3), CFrame.new(flatCenter + off + Vector3.new(0, 1, 0)), Color3.fromRGB(78, 152, 88), Enum.Material.Grass)
		bush.Shape = Enum.PartType.Ball
		bush.CanCollide = false
	end

	return territoryFolder
end

-- Архитектурные стили пяти тиров зданий мини-городка.
local TIER_STYLES = {
	[1] = { -- пляжный дом: дерево и терракотовая крыша
		wall = Color3.fromRGB(226, 202, 160), wallMat = Enum.Material.WoodPlanks,
		trim = Color3.fromRGB(140, 100, 62), roof = Color3.fromRGB(186, 88, 56), roofStyle = "gable",
		glass = Color3.fromRGB(150, 214, 232), glassMat = Enum.Material.Glass,
	},
	[2] = { -- прибрежный коттедж: пастельные стены, серо-синяя крыша
		wall = Color3.fromRGB(216, 236, 229), wallMat = Enum.Material.SmoothPlastic,
		trim = Color3.fromRGB(74, 112, 122), roof = Color3.fromRGB(62, 112, 128), roofStyle = "gable",
		glass = Color3.fromRGB(140, 210, 230), glassMat = Enum.Material.Glass,
	},
	[3] = { -- белая вилла: плоская крыша с садом
		wall = Color3.fromRGB(246, 246, 240), wallMat = Enum.Material.SmoothPlastic,
		trim = Color3.fromRGB(190, 194, 198), roof = Color3.fromRGB(232, 234, 238), roofStyle = "flat",
		glass = Color3.fromRGB(110, 205, 235), glassMat = Enum.Material.Glass,
	},
	[4] = { -- модерновый особняк: тёмный корпус, янтарное остекление, маяк
		wall = Color3.fromRGB(54, 60, 68), wallMat = Enum.Material.SmoothPlastic,
		trim = Color3.fromRGB(120, 126, 134), roof = Color3.fromRGB(44, 48, 54), roofStyle = "flat",
		glass = Color3.fromRGB(255, 152, 48), glassMat = Enum.Material.Neon, beacon = true,
	},
	[5] = { -- резиденция: башня с вертолётной площадкой и неоном
		wall = Color3.fromRGB(236, 240, 246), wallMat = Enum.Material.SmoothPlastic,
		trim = Color3.fromRGB(214, 178, 96), roof = Color3.fromRGB(226, 230, 238), roofStyle = "helipad",
		glass = Color3.fromRGB(242, 92, 190), glassMat = Enum.Material.Neon,
	},
}

-- Уникальные 3D модели зданий. Уровень прокачки = количество этажей: дом растёт
-- вверх с каждым уровнем. baseCF ставит дом фасадом (входом) к центру острова.
local function buildBuildingModel(plotId, slotIndex, tier, level, territoryFolder)
	local plot = PlotManager.GetPlot(plotId)
	local slotCenter = plot.slots[slotIndex].center + Vector3.new(0, 10, 0)
	-- Дверь/фасад дома смотрит по локальной -Z; направляем -Z на центр острова (к мосту).
	local baseCF = CFrame.lookAt(slotCenter, Vector3.new(plot.center.X, slotCenter.Y, plot.center.Z))

	local style = TIER_STYLES[tier]
	local home = Instance.new("Model")
	home.Name = "IncomeHome_" .. slotIndex
	home:SetAttribute("Alive", true)
	home.Parent = territoryFolder

	local width = 16 + tier * 2
	local depth = 14 + tier * 2
	local storeyH = 4.6
	local floors = math.clamp(level, 1, Config.MAX_BUILDING_LEVEL)

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

	-- Каменное основание (чуть шире дома, слегка утоплено в песок)
	lp("Foundation", Vector3.new(width + 2, 1.2, depth + 2), 0, 0, 0, Color3.fromRGB(168, 162, 152), Enum.Material.Concrete)

	-- Этажи: четыре стены + ленточное остекление на каждом этаже.
	for f = 1, floors do
		local y0 = 0.6 + (f - 1) * storeyH -- низ этажа
		local wallY = y0 + storeyH / 2
		local bandY = y0 + storeyH * 0.62

		lp("Wall_B" .. f, Vector3.new(width, storeyH, 1), 0, wallY, depth / 2, style.wall, style.wallMat)
		lp("Wall_L" .. f, Vector3.new(1, storeyH, depth), -width / 2, wallY, 0, style.wall, style.wallMat)
		lp("Wall_R" .. f, Vector3.new(1, storeyH, depth), width / 2, wallY, 0, style.wall, style.wallMat)

		local sideW = (width - 5) / 2
		if f == 1 then
			-- Фасад первого этажа со сквозным дверным проёмом
			lp("Wall_FL", Vector3.new(sideW, storeyH, 1), -(5 + sideW) / 2, wallY, -depth / 2, style.wall, style.wallMat)
			lp("Wall_FR", Vector3.new(sideW, storeyH, 1), (5 + sideW) / 2, wallY, -depth / 2, style.wall, style.wallMat)
			lp("DoorHeader", Vector3.new(5, storeyH - 3.4, 1), 0, y0 + storeyH - (storeyH - 3.4) / 2, -depth / 2, style.trim, Enum.Material.Wood)
		else
			lp("Wall_F" .. f, Vector3.new(width, storeyH, 1), 0, wallY, -depth / 2, style.wall, style.wallMat)
		end

		-- Ленточное остекление: полосы чуть отстоят от стен (нет копланарных граней)
		if f == 1 then
			lp("Band_FL" .. f, Vector3.new(sideW * 0.7, 1.5, 0.3), -(5 + sideW) / 2, bandY, -depth / 2 - 0.68, style.glass, style.glassMat)
			lp("Band_FR" .. f, Vector3.new(sideW * 0.7, 1.5, 0.3), (5 + sideW) / 2, bandY, -depth / 2 - 0.68, style.glass, style.glassMat)
		else
			lp("Band_F" .. f, Vector3.new(width * 0.8, 1.5, 0.3), 0, bandY, -depth / 2 - 0.68, style.glass, style.glassMat)
		end
		lp("Band_B" .. f, Vector3.new(width * 0.8, 1.5, 0.3), 0, bandY, depth / 2 + 0.68, style.glass, style.glassMat)
		lp("Band_L" .. f, Vector3.new(0.3, 1.5, depth * 0.8), -width / 2 - 0.68, bandY, 0, style.glass, style.glassMat)
		lp("Band_R" .. f, Vector3.new(0.3, 1.5, depth * 0.8), width / 2 + 0.68, bandY, 0, style.glass, style.glassMat)

		-- Межэтажный карниз
		if f < floors then
			lp("Slab" .. f, Vector3.new(width + 0.8, 0.35, depth + 0.8), 0, y0 + storeyH, 0, style.trim, Enum.Material.SmoothPlastic)
		end
	end

	local wallsTop = 0.6 + floors * storeyH

	-- Угловые пилястры на всю высоту — здание выглядит собранным, а не "коробкой"
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			lp("Pillar", Vector3.new(1.4, wallsTop, 1.4), sx * (width / 2), wallsTop / 2, sz * (depth / 2), style.trim, Enum.Material.SmoothPlastic)
		end
	end

	-- Крыльцо с навесом
	lp("Porch", Vector3.new(7, 0.7, 5), 0, 0.25, -depth / 2 - 2.5, Color3.fromRGB(128, 89, 50), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -2.8, 2.8 }) do
		lp("PorchPost", Vector3.new(0.7, 4.6, 0.7), x, 3.1, -depth / 2 - 4.3, style.trim, Enum.Material.Wood)
	end
	lp("PorchRoof", Vector3.new(8, 0.6, 3.4), 0, 5.6, -depth / 2 - 3.2, style.roof, Enum.Material.Slate, CFrame.Angles(math.rad(8), 0, 0))

	-- Крыша по стилю тира
	local roofCore
	if style.roofStyle == "gable" then
		-- Двускатная крыша с КОНЬКОМ (пик /\): внутренние края скатов выше внешних.
		roofCore = lp("RoofLeft", Vector3.new(width / 2 + 1, 1, depth + 2), -width / 4, wallsTop + 1.4, 0, style.roof, Enum.Material.Slate, CFrame.Angles(0, 0, math.rad(24)))
		lp("RoofRight", Vector3.new(width / 2 + 1, 1, depth + 2), width / 4, wallsTop + 1.4, 0, style.roof, Enum.Material.Slate, CFrame.Angles(0, 0, math.rad(-24)))
		lp("Chimney", Vector3.new(2.2, 5.5, 2.2), width * 0.27, wallsTop + 3.4, 2, Color3.fromRGB(96, 84, 74), Enum.Material.Brick)
	else
		-- Плоская крыша с парапетом
		roofCore = lp("RoofSlab", Vector3.new(width + 1.4, 0.8, depth + 1.4), 0, wallsTop + 0.4, 0, style.roof, Enum.Material.SmoothPlastic)
		lp("ParapetF", Vector3.new(width + 1.4, 1.1, 0.5), 0, wallsTop + 1.3, -(depth + 0.9) / 2, style.trim, Enum.Material.SmoothPlastic)
		lp("ParapetB", Vector3.new(width + 1.4, 1.1, 0.5), 0, wallsTop + 1.3, (depth + 0.9) / 2, style.trim, Enum.Material.SmoothPlastic)
		lp("ParapetL", Vector3.new(0.5, 1.1, depth + 1.4), -(width + 0.9) / 2, wallsTop + 1.3, 0, style.trim, Enum.Material.SmoothPlastic)
		lp("ParapetR", Vector3.new(0.5, 1.1, depth + 1.4), (width + 0.9) / 2, wallsTop + 1.3, 0, style.trim, Enum.Material.SmoothPlastic)

		if style.roofStyle == "helipad" then
			local padD = math.min(width, depth) * 0.72
			local helipad = lp("Helipad", Vector3.new(0.35, padD, padD), 0, wallsTop + 1.0, 0, Color3.fromRGB(58, 62, 70), Enum.Material.SmoothPlastic, CFrame.Angles(0, 0, math.rad(90)))
			helipad.Shape = Enum.PartType.Cylinder
			local ring = lp("HelipadRing", Vector3.new(0.15, padD + 1.6, padD + 1.6), 0, wallsTop + 1.55, 0, style.glass, Enum.Material.Neon, CFrame.Angles(0, 0, math.rad(90)))
			ring.Shape = Enum.PartType.Cylinder
			ring.Transparency = 0.25
			ring.CanCollide = false
			lp("Spire", Vector3.new(0.6, 8, 0.6), -width * 0.32, wallsTop + 4.6, depth * 0.3, style.trim, Enum.Material.Metal)
			local orb = lp("SpireOrb", Vector3.new(1.4, 1.4, 1.4), -width * 0.32, wallsTop + 9, depth * 0.3, style.glass, Enum.Material.Neon)
			orb.Shape = Enum.PartType.Ball
			orb.CanCollide = false
		else
			-- Сад на плоской крыше
			for i, off in ipairs({ { -width * 0.25, -depth * 0.2 }, { width * 0.28, depth * 0.22 }, { -width * 0.1, depth * 0.28 } }) do
				local bush = lp("RoofBush_" .. i, Vector3.new(2.4, 2, 2.4), off[1], wallsTop + 1.9, off[2], Color3.fromRGB(74, 150, 84), Enum.Material.Grass)
				bush.Shape = Enum.PartType.Ball
				bush.CanCollide = false
			end
			if style.beacon then
				lp("Antenna", Vector3.new(0.4, 6, 0.4), width * 0.3, wallsTop + 3.8, depth * 0.25, Color3.fromRGB(200, 204, 210), Enum.Material.Metal)
				local beacon = lp("Beacon", Vector3.new(0.9, 0.9, 0.9), width * 0.3, wallsTop + 7, depth * 0.25, Color3.fromRGB(255, 70, 60), Enum.Material.Neon)
				beacon.Shape = Enum.PartType.Ball
				beacon.CanCollide = false
			end
		end
	end

	-- Статичной таблички «ур.N +$X» над зданием больше НЕТ (чистый экран):
	-- прибыль видно по всплывающим «+$» (VisualFX), уровень — по этажам дома.
	return home, roofCore, nil, nil
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

	-- ВАЖНО: ценник обновляем ПОСЛЕ записи нового уровня. Раньше он вызывался ДО
	-- записи и показывал цену ПРОШЛОГО шага — «пишет $100, а списывается $160».
	updatePriceTag(plotId, slotIndex)

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
		local money = DataManager.GetMoney(player)
		if money < base.cost then
			-- Красная вспышка счётчика на клиенте: денег не хватает.
			Remotes.Get("Notify"):FireClient(player, string.format("Нужно ещё $%d", base.cost - money), "error")
			return
		end
		DataManager.AddMoney(player, -base.cost)
		spawnBuilding(plotId, slotIndex, 1)
		print(string.format("[FarmManager] %s построил %s (ур.1)", player.Name, base.name))
	else
		-- ПРОКАЧКА до следующего уровня.
		if not data.alive then return end
		if data.level >= Config.MAX_BUILDING_LEVEL then return end
		local nextLevel = data.level + 1
		local cost = Config.UpgradeCost(slotIndex, nextLevel)
		local money = DataManager.GetMoney(player)
		if money < cost then
			Remotes.Get("Notify"):FireClient(player, string.format("Нужно ещё $%d", cost - money), "error")
			return
		end
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

-- Анти-двойное списание: после срабатывания кнопки игрок обязан СОЙТИ с неё
-- (отойти от центра дальше радиуса), прежде чем она сработает снова. Раньше,
-- стоя на кнопке, Touched стрелял повторно каждую секунду — списывалось больше,
-- чем показывал ценник (баг «стоит 410, списалось ~700»).
local padLock = {} -- [key] = { player, pos, radius }

task.spawn(function()
	while true do
		task.wait(0.25)
		for key, rec in pairs(padLock) do
			local char = rec.player and rec.player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not rec.player.Parent or not hrp then
				padLock[key] = nil
			else
				local flat = Vector3.new(hrp.Position.X - rec.pos.X, 0, hrp.Position.Z - rec.pos.Z)
				if flat.Magnitude > rec.radius then
					padLock[key] = nil
				end
			end
		end
	end
end)

function FarmManager.Init()
	for plotId, plot in pairs(PlotManager.GetAllPlots()) do
		for slotIdx, slotInfo in ipairs(plot.slots) do
			-- Покупка/прокачка по НАСТУПАНИЮ на кнопку: ровно ОДИН раз за визит.
			slotInfo.buyPad.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if not player or plot.owner ~= player then return end
				local key = string.format("%d:%d:%d", player.UserId, plotId, slotIdx)
				if padLock[key] then return end
				padLock[key] = { player = player, pos = slotInfo.buyPad.Position, radius = 7 }
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
