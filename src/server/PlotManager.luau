-- PlotManager.luau - ocean world, sandy islands, wildlife, launchers, and rocket pads
--
-- v3: восемь КРУПНЫХ островов кольцом вокруг пустого центра (центральный остров
-- убран). На каждом острове 4 ракетных стенда; перед каждым — зелёный круг
-- покупки/прокачки. Внешний вид ракеты меняется каждые 5 уровней (Mark I..IV),
-- геометрия ракеты общая с летящей ракетой (см. RocketFactory).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)
local Config            = require(sharedFolder:WaitForChild("Config"))
local RocketFactory     = require(script.Parent:WaitForChild("RocketFactory"))
local MeshLibrary       = require(script.Parent:WaitForChild("MeshLibrary"))

local PlotManager = {}

local plots = {}
local playerPlot = {}

local PLOT_THEME_COLORS = {
	Color3.fromRGB(46, 117, 224),  -- синий
	Color3.fromRGB(224, 76, 46),   -- красный
	Color3.fromRGB(46, 200, 90),   -- зелёный
	Color3.fromRGB(230, 180, 30),  -- жёлтый
	Color3.fromRGB(170, 50, 230),  -- фиолетовый
	Color3.fromRGB(40, 210, 210),  -- бирюзовый
	Color3.fromRGB(240, 120, 190), -- розовый
	Color3.fromRGB(255, 130, 40),  -- оранжевый
}

-- Высота ходибельной песчаной поверхности острова над Y центра плота.
-- Все объекты (спавн, кнопки, ракеты, пальмы) выравниваются по этой высоте.
local SURFACE_OFFSET = 10

local function makePart(parent, name, size, cframe, color, material)
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

-- Вспомогательные конструкторы для цилиндров и клиньев
local function makeCylinder(parent, name, height, diameter, position, color, material)
	-- Цилиндр в Roblox лежит вдоль локальной оси X; поворотом на 90° по Z ставим вертикально.
	local part = makePart(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

local function makeWedge(parent, name, size, cframe, color, material)
	local part = Instance.new("WedgePart")
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

-- Акула плавает ПОД водой и периодически всплывает так, что над поверхностью
-- видно ТОЛЬКО спинной плавник (как в кино) — тело никогда не выходит из воды.
local function buildShark(parent, index)
	local model = Instance.new("Model")
	model.Name = "Shark_" .. index
	model.Parent = parent

	-- Центр карты — пустая вода: акулы кружат именно там.
	local radius = 130 + (index % 4) * 70
	local angle = index / 16 * math.pi * 2
	local body = makePart(model, "Body", Vector3.new(4, 4, 13), CFrame.new(), Color3.fromRGB(67, 88, 101), Enum.Material.SmoothPlastic)
	body.Shape = Enum.PartType.Ball
	body.CanCollide = false
	local fin = makePart(model, "Fin", Vector3.new(0.7, 5, 5), CFrame.new(), body.Color, Enum.Material.SmoothPlastic)
	fin.CanCollide = false
	local tail = makePart(model, "Tail", Vector3.new(0.8, 7, 5), CFrame.new(), body.Color, Enum.Material.SmoothPlastic)
	tail.CanCollide = false
	model.PrimaryPart = body

	task.spawn(function()
		local t = angle
		local phase = index * 1.3
		-- Глубина "дышит" синусом: от -13 (глубоко) до -3 (у самой поверхности).
		-- На пике всплытия верх тела остаётся под водой, наружу торчит только плавник.
		local function depthAt(tt)
			return (Config.WATER_LEVEL - 3) - (math.sin(tt * 2.2 + phase) + 1) * 5
		end
		while model.Parent do
			t += 0.007
			local y = depthAt(t)
			local position = Vector3.new(math.cos(t) * radius, y, math.sin(t) * radius)
			local nextPosition = Vector3.new(math.cos(t + 0.03) * radius, depthAt(t + 0.03), math.sin(t + 0.03) * radius)
			model:PivotTo(CFrame.lookAt(position, nextPosition))
			fin.CFrame = body.CFrame * CFrame.new(0, 3, 1) * CFrame.Angles(0, 0, math.rad(45))
			tail.CFrame = body.CFrame * CFrame.new(0, 0, 7)
			task.wait(0.05)
		end
	end)
end

local function buildOcean()
	local terrain = workspace.Terrain
	terrain:Clear()
	-- Тропическая бирюзовая вода из Terrain (не плоский Part): мягкие блики,
	-- лёгкая волна, полупрозрачная толща — острова стоят заметно выше уровня воды.
	terrain.WaterColor = Color3.fromRGB(33, 171, 176)
	terrain.WaterTransparency = 0.7
	terrain.WaterReflectance = 0.4
	terrain.WaterWaveSize = 0.15
	terrain.WaterWaveSpeed = 12

	local waterDepth = Config.WATER_LEVEL - Config.SEABED_LEVEL
	terrain:FillBlock(
		CFrame.new(0, Config.SEABED_LEVEL + waterDepth / 2, 0),
		Vector3.new(Config.WORLD_SIZE, waterDepth, Config.WORLD_SIZE),
		Enum.Material.Water
	)
	terrain:FillBlock(
		CFrame.new(0, Config.SEABED_LEVEL - 5, 0),
		Vector3.new(Config.WORLD_SIZE, 10, Config.WORLD_SIZE),
		Enum.Material.Sand
	)

	-- Лёгкие кучевые облака над океаном (красивое небо почти бесплатно).
	local clouds = terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = terrain
	end
	clouds.Cover = 0.42
	clouds.Density = 0.24
	clouds.Color = Color3.fromRGB(234, 241, 248)

	local world = Instance.new("Folder")
	world.Name = "OceanWildlife"
	world.Parent = workspace
	for index = 1, 16 do
		buildShark(world, index)
	end
end

-- Остров. Если в ReplicatedStorage лежит ЛЕГО-МЕШ из Blender
-- (IslandMeshes/MainIsland, см. assets/island/main_island.py) — используем его:
-- зелёная стад-плита, дорога с пунктиром, газон и зона ракет с чёрно-жёлтой
-- лентой. Иначе фолбэк: вложенные сплошные цилиндры (никаких перекрывающихся
-- копланарных партов → нет "дрожащего песка"/z-fighting).
local function tryBuildIslandMesh(folder, position)
	-- Понимает и «MainIsland», и имя файла «main_island» (Import 3D), в папке
	-- IslandMeshes, общей папке Meshes или прямо в ReplicatedStorage.
	local template = MeshLibrary.Find(Config.ISLAND.FOLDER, { Config.ISLAND.MAIN, "main_island" })
	if not template then return nil end

	-- Import 3D мог разбить остров на НЕСКОЛЬКО MeshPart (по материалам) внутри
	-- Model — работаем с моделью целиком: ScaleTo + GetBoundingBox.
	local clone = template:Clone()
	local model
	if clone:IsA("Model") then
		model = clone
	elseif clone:IsA("BasePart") then
		model = Instance.new("Model")
		clone.Parent = model
	else
		clone:Destroy()
		return nil
	end
	model.Name = "MainIsland"

	local anyPart = model:FindFirstChildWhichIsA("BasePart", true)
	if not anyPart then
		model:Destroy()
		return nil
	end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = true
			p.CanCollide = true
		end
	end
	if not model.PrimaryPart then model.PrimaryPart = anyPart end

	local _, bbSize = model:GetBoundingBox()
	local scale = Config.ISLAND.MAIN_WIDTH / math.max(bbSize.X, bbSize.Z, 0.001)
	model:ScaleTo(model:GetScale() * scale)

	-- YAW кладёт зону ракет (чёрно-жёлтая лента) на север, под стенды; верх меша
	-- (зелёная плита) = уровень ходибельной поверхности острова.
	model:PivotTo(CFrame.new(position.X, position.Y, position.Z) * CFrame.Angles(0, math.rad(Config.ISLAND.YAW), 0))
	local bbCF, bbSize2 = model:GetBoundingBox()
	local desired = Vector3.new(position.X, position.Y + SURFACE_OFFSET - bbSize2.Y / 2, position.Z)
	model:TranslateBy(desired - bbCF.Position)
	-- Гарантированный вид: по умолчанию срезаем текстуры и красим части
	-- плоскими лего-цветами по именам материалов (см. Config.ISLAND.USE_TEXTURES —
	-- свежезалитые текстуры Roblox может отдавать чёрными).
	MeshLibrary.ApplyIslandLook(model, Config.ISLAND.USE_TEXTURES)
	model.Parent = folder
	return model
end

-- СТАРЫХ КРУГЛЫХ ОСТРОВОВ БОЛЬШЕ НЕТ. Основной путь — лего-меш из Blender
-- (main_island). Если меш не импортирован — минимальный КВАДРАТНЫЙ лего-остров
-- из партов (зелёная плита + песочная кайма + ступени обрыва), чтобы игра
-- работала, а стиль не ломался.
local function buildIslandBase(folder, position, sandColor)
	local sandRadius = Config.PLOT_CENTER_SIZE * 0.64

	local islandMesh = tryBuildIslandMesh(folder, position)
	if islandMesh then
		return islandMesh, sandRadius
	end

	warn(string.format("[PlotManager] Меш острова (main_island) не найден в ReplicatedStorage — строю простой квадратный фолбэк. См. assets/IMPORT_GUIDE.md"))

	local size = Config.ISLAND.MAIN_WIDTH
	-- Зелёная стад-плита (верх = position.Y + SURFACE_OFFSET)
	local green = makePart(folder, "GreenPlate", Vector3.new(size, 2.4, size),
		CFrame.new(position + Vector3.new(0, SURFACE_OFFSET - 1.2, 0)), Color3.fromRGB(86, 165, 54), Enum.Material.SmoothPlastic)
	-- Песочная кайма чуть ниже и шире
	makePart(folder, "SandRim", Vector3.new(size + 22, 2.4, size + 22),
		CFrame.new(position + Vector3.new(0, SURFACE_OFFSET - 3.0, 0)), sandColor, Enum.Material.SmoothPlastic)
	-- Ступени обрыва в воду + каменное дно
	makePart(folder, "CliffStep1", Vector3.new(size + 12, 8, size + 12),
		CFrame.new(position + Vector3.new(0, SURFACE_OFFSET - 8.4, 0)), Color3.fromRGB(226, 176, 88), Enum.Material.SmoothPlastic)
	makePart(folder, "CliffStep2", Vector3.new(size - 6, 8, size - 6),
		CFrame.new(position + Vector3.new(0, SURFACE_OFFSET - 16.4, 0)), Color3.fromRGB(196, 148, 70), Enum.Material.SmoothPlastic)
	makePart(folder, "RockBase", Vector3.new(size - 26, 6, size - 26),
		CFrame.new(position + Vector3.new(0, SURFACE_OFFSET - 23.4, 0)), Color3.fromRGB(88, 90, 94), Enum.Material.Slate)

	return green, sandRadius
end

-- Деревянный трап с воды на южный берег: выпал за остров — заплыл к трапу
-- и поднялся обратно (раньше с воды было не залезть).
local function buildReturnRamp(folder, position)
	local ramp = makeWedge(
		folder,
		"ReturnRamp",
		Vector3.new(10, 22, 48),
		-- lookAt от острова: локальный +Z (высокая грань клина) смотрит на остров.
		CFrame.lookAt(position + Vector3.new(0, -1, 112), position + Vector3.new(0, -1, 200)),
		Color3.fromRGB(128, 90, 50),
		Enum.Material.WoodPlanks
	)
	ramp.CanCollide = true

	-- Пара свай у нижнего (водного) конца трапа
	for _, x in ipairs({ -4, 4 }) do
		makeCylinder(folder, "RampPost", 14, 1.4, position + Vector3.new(x, -17, 128), Color3.fromRGB(73, 52, 34), Enum.Material.Wood)
	end
end

-- Большая красивая пальма: изогнутый ствол из сегментов-цилиндров, крона из листьев и кокосы.
local function buildPalm(parent, basePos, yawDeg, scale)
	local model = Instance.new("Model")
	model.Name = "Palm"
	model.Parent = parent

	local segCount = math.random(4, 6)
	local segLen = 3.1 * scale
	local dia = 1.7 * scale
	local trunkColor = Color3.fromRGB(111, 77, 43)
	local lean = math.rad(6) -- лёгкий изгиб ствола сегмент за сегментом

	local growth = CFrame.new(basePos) * CFrame.Angles(0, math.rad(yawDeg), 0)
	for i = 1, segCount do
		local d = dia * (1 - (i - 1) * 0.09)
		local centerCF = growth * CFrame.new(0, segLen / 2, 0)
		local seg = makePart(model, "Trunk_" .. i, Vector3.new(segLen + 0.35, d, d), centerCF * CFrame.Angles(0, 0, math.rad(90)), trunkColor, Enum.Material.Wood)
		seg.Shape = Enum.PartType.Cylinder
		growth = growth * CFrame.new(0, segLen, 0) * CFrame.Angles(lean, 0, 0)
	end

	local crownPos = growth.Position

	-- 6-8 больших изогнутых листьев, наклонённых вниз от вершины
	local leaves = math.random(6, 8)
	local leafLen = 11 * scale
	for i = 1, leaves do
		local leafAngle = math.rad((360 / leaves) * i)
		local droop = -math.rad(26 + math.random(0, 14))
		local leafCF = CFrame.new(crownPos)
			* CFrame.Angles(0, leafAngle, 0)
			* CFrame.Angles(droop, 0, 0)
			* CFrame.new(0, 0, -leafLen / 2)
		local leaf = makePart(model, "Leaf_" .. i, Vector3.new(2.7 * scale, 0.4, leafLen), leafCF, Color3.fromRGB(53, 133, 71), Enum.Material.Grass)
		leaf.CanCollide = false
	end

	-- Плотная зелёная шапка в центре кроны
	local cap = makePart(model, "Crown", Vector3.new(2.6 * scale, 2 * scale, 2.6 * scale), CFrame.new(crownPos), Color3.fromRGB(60, 120, 66), Enum.Material.Grass)
	cap.Shape = Enum.PartType.Ball
	cap.CanCollide = false

	-- Пара кокосов под кроной
	for i = 1, 2 do
		local a = math.rad(i * 150 + 30)
		local coconut = makePart(model, "Coconut_" .. i, Vector3.new(1.2 * scale, 1.2 * scale, 1.2 * scale), CFrame.new(crownPos + Vector3.new(math.cos(a) * 1.7, -1.5 * scale, math.sin(a) * 1.7)), Color3.fromRGB(74, 47, 25), Enum.Material.SmoothPlastic)
		coconut.Shape = Enum.PartType.Ball
		coconut.CanCollide = false
	end

	return model
end

-- Декор острова: РОВНО ДВЕ пальмы (не преувеличиваем). Blender-меши PalmA и
-- PalmB смотрят в разные стороны (ReplicatedStorage/PalmMeshes, см.
-- assets/palm_trees); пока мешей нет — две процедурные пальмы с разными яу.
local function tryPlacePalmMesh(decor, spot, basePos, yawDeg)
	-- Понимает и «PalmA/PalmB», и имена файлов «palm_a/palm_b» (Import 3D).
	local meshPart = MeshLibrary.FindPart(Config.PALMS.FOLDER, { spot.name, spot.file })
	if not meshPart then return nil end

	local scale = Config.PALMS.HEIGHT / math.max(meshPart.Size.Y, 0.001)
	meshPart.Name = spot.name
	meshPart.Size = meshPart.Size * scale
	meshPart.Anchored = true
	meshPart.CanCollide = true
	meshPart.CFrame = CFrame.new(basePos + Vector3.new(0, meshPart.Size.Y / 2, 0))
		* CFrame.Angles(0, math.rad(yawDeg), 0)
	meshPart.Parent = decor
	return meshPart
end

local function buildIslandDecor(parent, position, plotId)
	local decor = Instance.new("Folder")
	decor.Name = "IslandDecor"
	decor.Parent = parent

	for _, spot in ipairs(Config.PALMS.SPOTS) do
		local basePos = position + Vector3.new(spot.offset.X, SURFACE_OFFSET, spot.offset.Z)
		if not tryPlacePalmMesh(decor, spot, basePos, spot.yaw) then
			-- Фолбэк: процедурная пальма (яу разные — «смотрят в разные стороны»)
			buildPalm(decor, basePos, spot.yaw, 1.1)
		end
	end
end

local function buildIslandModel(plotId, position)
	local folder = Instance.new("Folder")
	folder.Name = "Plot_" .. plotId
	folder:SetAttribute("PlotId", plotId)
	folder:SetAttribute("OwnerUserId", 0)
	folder.Parent = workspace

	local themeColor = PLOT_THEME_COLORS[plotId] or Color3.fromRGB(150, 150, 150)

	-- Единые сплошные цилиндры вместо перекрывающихся сегментов (устраняет z-fighting песка).
	-- Тёплый золотистый песок вместо белёсого.
	buildIslandBase(folder, position, Color3.fromRGB(240, 202, 116))
	buildIslandDecor(folder, position, plotId)
	buildReturnRamp(folder, position)

	-- Спавн НЕВИДИМ: раньше это был "второй квадрат песка", плававший над пляжем
	-- рядом с ракетой. Точка респавна работает, но геометрии больше не видно.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlotSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = position + Vector3.new(0, SURFACE_OFFSET + 1.05, 40)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = false
	spawn.Duration = 0
	spawn.Parent = folder

	-- Launcher models are added here as the player expands from one to four.
	local siloFolder = Instance.new("Folder")
	siloFolder.Name = "RocketSilo"
	siloFolder.Parent = folder

	-- Кнопки покупки зданий — плоские зелёные "блины" у кромки песка. Покупка/прокачка
	-- срабатывает по НАСТУПАНИЮ (Touched). Над каждой висит ценник (BillboardGui).
	local slotsData = {}
	local edgeR = Config.PLOT_CENTER_SIZE * 0.64 - 8
	for slotIdx, offset in ipairs(Config.SLOT_OFFSETS) do
		local dir = offset.Unit
		local edgePos = position + dir * edgeR
		-- Сдвигаем кнопку ВБОК от радиальной линии (по ней идёт мост/тропа) и слегка
		-- приподнимаем над песком: кнопка не пересекает мост, а её нижняя грань
		-- не копланарна песку (нет z-fighting).
		local side = dir:Cross(Vector3.new(0, 1, 0))
		local padPos = edgePos + side * 9 + Vector3.new(0, SURFACE_OFFSET + 0.8, 0)

		local buyPad = Instance.new("Part")
		buyPad.Name = "BuyPad_" .. slotIdx
		buyPad.Shape = Enum.PartType.Cylinder
		buyPad.Anchored = true
		buyPad.Size = Vector3.new(0.6, 8, 8)
		buyPad.Orientation = Vector3.new(0, 0, 90)
		buyPad.Position = padPos
		buyPad.Color = Color3.fromRGB(69, 200, 110)
		buyPad.Material = Enum.Material.Neon
		if slotIdx > 1 then
			-- Заблокированные слоты скрыты до постройки предыдущего.
			buyPad.Transparency = 1
			buyPad.CanCollide = false
		end
		buyPad.Parent = folder

		-- Ценник над кнопкой. Enabled = false: видимостью управляет клиент
		-- (PriceTags) — ценники показываются ТОЛЬКО на своём острове и ТОЛЬКО
		-- когда игрок стоит рядом (меньше текста на экране). Атрибут Unlocked
		-- отражает, открыт ли слот (последовательное открытие слотов).
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "PriceTag"
		billboard.Size = UDim2.new(0, 150, 0, 44)
		billboard.StudsOffset = Vector3.new(0, 5, 0)
		billboard.AlwaysOnTop = true
		billboard.Enabled = false
		billboard:SetAttribute("Unlocked", slotIdx == 1)
		billboard.Parent = buyPad

		-- Жирный читаемый шрифт (тонкий Medium выглядел «мерзко» на фоне мира).
		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "PriceLabel"
		priceLabel.Size = UDim2.new(1, 0, 1, 0)
		priceLabel.BackgroundTransparency = 1
		priceLabel.TextScaled = false
		priceLabel.TextSize = 16
		priceLabel.Font = Enum.Font.GothamBold
		priceLabel.TextColor3 = Color3.fromRGB(245, 248, 250)
		priceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		priceLabel.TextStrokeTransparency = 0.35
		local cfg = Config.FARM_TYPES[slotIdx]
		priceLabel.Text = string.format("%s\n$%d", cfg.name, cfg.cost)
		priceLabel.Parent = billboard

		slotsData[slotIdx] = {
			center = position + offset,
			edgePos = edgePos,
			buyPad = buyPad,
			billboard = billboard,
			priceLabel = priceLabel,
		}
	end

	-- Зелёные круги ракет: ПЕРЕД каждым из 4 стендов. Наступание = покупка стенда
	-- (если ещё не куплен) или прокачка ракеты (если куплен). Состоянием управляет
	-- RocketManager через PlotManager.SetRocketPadState.
	local rocketPads = {}
	for padIdx, offset in ipairs(Config.LAUNCHER_OFFSETS) do
		local padPos = position + Vector3.new(offset.X, SURFACE_OFFSET + 0.55, offset.Z + Config.LAUNCHER_PAD_FORWARD)

		local pad = Instance.new("Part")
		pad.Name = "RocketPad_" .. padIdx
		pad.Shape = Enum.PartType.Cylinder
		pad.Anchored = true
		pad.Size = Vector3.new(0.5, 10, 10)
		pad.Orientation = Vector3.new(0, 0, 90)
		pad.Position = padPos
		pad.Color = Color3.fromRGB(64, 224, 130)
		pad.Material = Enum.Material.Neon
		pad.Transparency = 1
		pad.CanCollide = false
		pad.Parent = folder

		local billboard = Instance.new("BillboardGui")
		billboard.Name = "PriceTag"
		billboard.Size = UDim2.new(0, 170, 0, 48)
		billboard.StudsOffset = Vector3.new(0, 5, 0)
		billboard.AlwaysOnTop = true
		billboard.Enabled = false
		billboard:SetAttribute("Unlocked", false)
		billboard.Parent = pad

		local label = Instance.new("TextLabel")
		label.Name = "PriceLabel"
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.TextScaled = false
		label.TextSize = 16
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromRGB(245, 248, 250)
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.35
		label.Text = ""
		label.Parent = billboard

		rocketPads[padIdx] = { pad = pad, billboard = billboard, label = label }
	end

	plots[plotId] = {
		owner = nil,
		folder = folder,
		center = position,
		spawn = spawn,
		slots = slotsData,
		rocketPads = rocketPads,
		themeColor = themeColor,
		launchers = {},
	}
end

local function assignPlayerToPlot(player)
	for id, plot in pairs(plots) do
		if plot.owner == nil then
			plot.owner = player
			playerPlot[player] = id
			player:SetAttribute("PlotId", id)
			plot.folder:SetAttribute("OwnerUserId", player.UserId)
			player.RespawnLocation = plot.spawn

			local char = player.Character or player.CharacterAdded:Wait()
			if char then
				task.wait(0.2)
				char:PivotTo(plot.spawn.CFrame + Vector3.new(0, 4, 0))
			end

			print(string.format("[PlotManager] %s успешно назначен на Остров #%d", player.Name, id))
			break
		end
	end
end

function PlotManager.Init()
	local oldWildlife = workspace:FindFirstChild("OceanWildlife")
	if oldWildlife then oldWildlife:Destroy() end
	-- Центральный остров убран: центр карты — открытая вода с акулами.
	local oldCentral = workspace:FindFirstChild("CentralIsland")
	if oldCentral then oldCentral:Destroy() end
	-- Убираем «зелёную поляну под водой» — Baseplate/спавн из шаблона Studio,
	-- если они остались в place-файле (по ним и "ходили" акулы).
	for _, strayName in ipairs({ "Baseplate", "SpawnLocation" }) do
		local stray = workspace:FindFirstChild(strayName)
		if stray then stray:Destroy() end
	end

	buildOcean()

	for i, pos in ipairs(Config.PLOT_POSITIONS) do
		buildIslandModel(i, pos)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			local plotId = playerPlot[player]
			if plotId and plots[plotId] then
				task.wait(0.2)
				char:PivotTo(plots[plotId].spawn.CFrame + Vector3.new(0, 4, 0))
			end
		end)
		assignPlayerToPlot(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if not playerPlot[player] then
			assignPlayerToPlot(player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		local id = playerPlot[player]
		if id then
			local plot = plots[id]
			if plot then
				plot.owner = nil
				plot.folder:SetAttribute("OwnerUserId", 0)
				plot.folder.RocketSilo:ClearAllChildren()
				plot.launchers = {}
				PlotManager.ResetRocketPads(id)
			end
			playerPlot[player] = nil
		end
	end)

	-- Страховка «выпал за карту»: раз в 3 секунды возвращаем на спавн тех, кто
	-- провалился под дно или уплыл за границу мира.
	task.spawn(function()
		local half = Config.WORLD_SIZE / 2 + 60
		while true do
			task.wait(3)
			for _, player in ipairs(Players:GetPlayers()) do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hrp then
					local p = hrp.Position
					if p.Y < Config.SEABED_LEVEL - 2 or math.abs(p.X) > half or math.abs(p.Z) > half then
						local id = playerPlot[player]
						local plot = id and plots[id]
						if plot then
							char:PivotTo(plot.spawn.CFrame + Vector3.new(0, 4, 0))
						end
					end
				end
			end
		end
	end)
end

-- Создание стенда с ракетой нужного поколения (level определяет Mark).
function PlotManager.CreateLauncher(player, launcherIndex, level)
	local _, plot = PlotManager.GetPlotByPlayer(player)
	if not plot then return nil end
	if plot.launchers[launcherIndex] then return plot.launchers[launcherIndex] end
	local offset = Config.LAUNCHER_OFFSETS[launcherIndex]
	if not offset then return nil end

	local mark = Config.RocketMark(level or 1)
	local model = Instance.new("Model")
	model.Name = "Launcher_" .. launcherIndex
	model:SetAttribute("LauncherIndex", launcherIndex)
	model:SetAttribute("RocketMark", mark)
	model.Parent = plot.folder:FindFirstChild("RocketSilo")

	local teamColor = plot.themeColor
	-- Ракета СТОИТ на песке: считаем уровень песка и ставим на него бетонную площадку.
	local sandY = plot.center.Y + SURFACE_OFFSET
	local basePos = Vector3.new(plot.center.X + offset.X, sandY, plot.center.Z + offset.Z)

	-- Бетонная площадка лежит на лужайке; нижняя грань не копланарна поверхности.
	local pad = makeCylinder(model, "Pad", 0.4, 13, basePos + Vector3.new(0, 0.45, 0), Color3.fromRGB(148, 150, 156), Enum.Material.Concrete)
	local rim = makeCylinder(model, "ReadyRim", 0.5, 14.4, basePos + Vector3.new(0, 0.66, 0), teamColor, Enum.Material.Neon)
	rim.CanCollide = false

	-- Стенд: ЛЕГО-МЕШ ракеты (rocket_mkN из Blender, чем выше Mark — тем крупнее),
	-- та же высота, что у процедурной, чтобы точка старта не поехала.
	-- Фолбэк — общий конструктор RocketFactory (как у летящей ракеты).
	local parts, window, height
	local meshRocket = MeshLibrary.FindPart(Config.ROCKETS.FOLDER, { "Mk" .. mark, "rocket_mk" .. mark })
	if meshRocket then
		height = RocketFactory.GetHeight(mark, 1)
		local scale = height / math.max(meshRocket.Size.Y, 0.001)
		meshRocket.Name = "RocketMesh"
		meshRocket.Size = meshRocket.Size * scale
		meshRocket.Anchored = true
		meshRocket.CanCollide = true
		meshRocket.CFrame = CFrame.new(basePos + Vector3.new(0, 0.65 + meshRocket.Size.Y / 2, 0))
		meshRocket.Parent = model
		parts = { meshRocket }
		window = nil
	else
		parts, window, height = RocketFactory.Build(model, CFrame.new(basePos + Vector3.new(0, 0.65, 0)), teamColor, mark, 1, true)
	end
	local origin = Vector3.new(basePos.X, basePos.Y + 0.65 + height + 2, basePos.Z)

	-- Запуск идёт через прицел (клавиша E на стенде), см. HudManager.

	model.PrimaryPart = pad
	plot.launchers[launcherIndex] = { model = model, parts = parts, window = window, rim = rim, origin = origin, mark = mark }
	return plot.launchers[launcherIndex]
end

-- Полная перестройка стенда (эволюция внешнего вида каждые 5 уровней).
function PlotManager.RebuildLauncher(player, launcherIndex, level)
	local _, plot = PlotManager.GetPlotByPlayer(player)
	if not plot then return nil end
	local launcher = plot.launchers[launcherIndex]
	if launcher and launcher.model then
		launcher.model:Destroy()
	end
	plot.launchers[launcherIndex] = nil
	return PlotManager.CreateLauncher(player, launcherIndex, level)
end

function PlotManager.SetLauncherReady(player, launcherIndex, ready)
	local _, plot = PlotManager.GetPlotByPlayer(player)
	local launcher = plot and plot.launchers[launcherIndex]
	if not launcher then return end
	local t = ready and 0 or 1
	for _, p in ipairs(launcher.parts) do
		p.Transparency = t
	end
	if launcher.window then launcher.window.Transparency = ready and 0.15 or 1 end
	if launcher.rim then launcher.rim.Color = ready and plot.themeColor or Color3.fromRGB(85, 91, 95) end
end

function PlotManager.GetLauncherOrigin(player, launcherIndex)
	local _, plot = PlotManager.GetPlotByPlayer(player)
	local launcher = plot and plot.launchers[launcherIndex]
	return launcher and launcher.origin
end

-- === Зелёные круги ракет ===
-- state: "buy" (купить стенд), "upgrade" (прокачать), "max" (потолок), "locked" (скрыт).
local ROCKET_PAD_COLORS = {
	buy = Color3.fromRGB(64, 224, 130),
	upgrade = Color3.fromRGB(64, 224, 130),
	max = Color3.fromRGB(240, 196, 90),
}

function PlotManager.SetRocketPadState(plotId, index, state, text)
	local plot = plots[plotId]
	local rp = plot and plot.rocketPads and plot.rocketPads[index]
	if not rp then return end

	if state == "locked" then
		rp.pad.Transparency = 1
		rp.pad.CanCollide = false
		rp.billboard:SetAttribute("Unlocked", false)
	else
		rp.pad.Transparency = state == "max" and 0.35 or 0
		rp.pad.CanCollide = state ~= "max"
		rp.pad.Color = ROCKET_PAD_COLORS[state] or ROCKET_PAD_COLORS.buy
		rp.billboard:SetAttribute("Unlocked", true)
		rp.label.Text = text or ""
		rp.label.TextColor3 = state == "max" and Color3.fromRGB(255, 224, 150) or Color3.fromRGB(240, 244, 246)
	end
end

function PlotManager.ResetRocketPads(plotId)
	for index = 1, Config.MAX_LAUNCHERS do
		PlotManager.SetRocketPadState(plotId, index, "locked")
	end
end

function PlotManager.GetPlotByPlayer(player)
	local id = playerPlot[player]
	return id, plots[id]
end

function PlotManager.GetPlot(plotId)
	return plots[plotId]
end

function PlotManager.GetAllPlots()
	return plots
end

function PlotManager.GetPlayerByPlot(plotId)
	local plot = plots[plotId]
	return plot and plot.owner
end

return PlotManager
