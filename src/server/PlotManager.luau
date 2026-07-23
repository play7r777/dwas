-- PlotManager.luau - ocean world, sandy islands, wildlife, launchers, and rocket pads
--
-- v3: восемь КРУПНЫХ островов кольцом вокруг пустого центра (центральный остров
-- убран). На каждом острове 4 ракетных стенда; перед каждым — зелёный круг
-- покупки/прокачки. Внешний вид ракеты меняется каждые 5 уровней (Mark I..IV).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)
local Config            = require(sharedFolder:WaitForChild("Config"))

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

local function buildShark(parent, index)
	local model = Instance.new("Model")
	model.Name = "Shark_" .. index
	model.Parent = parent

	-- Центр карты теперь пустая вода — акулы кружат именно там.
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
		while model.Parent do
			t += 0.007
			local position = Vector3.new(math.cos(t) * radius, Config.WATER_LEVEL - 15, math.sin(t) * radius)
			local nextPosition = Vector3.new(math.cos(t + 0.03) * radius, position.Y, math.sin(t + 0.03) * radius)
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

-- Остров = набор ВЛОЖЕННЫХ сплошных цилиндров с верхними гранями на РАЗНОЙ высоте.
-- Никаких перекрывающихся копланарных партов → нет "плавающего/дрожащего песка" (z-fighting).
local function buildIslandBase(folder, position, sandColor)
	local scale = Config.PLOT_CENTER_SIZE
	local sandRadius = scale * 0.64

	-- Подводный риф (самый широкий, спрятан под каменным шельфом)
	makeCylinder(folder, "SubmergedReef", 20, (sandRadius * 2.3) + 12, position + Vector3.new(0, -20, 0), Color3.fromRGB(52, 73, 78), Enum.Material.Slate)
	-- Каменный шельф (верх +4 относительно position.Y)
	makeCylinder(folder, "RockShelf", 16, sandRadius * 2.14, position + Vector3.new(0, -4, 0), Color3.fromRGB(92, 87, 75), Enum.Material.Rock)
	-- Песчаная поверхность единым партом (верх = position.Y + SURFACE_OFFSET)
	local sand = makeCylinder(folder, "SandShore", 8, sandRadius * 2, position + Vector3.new(0, SURFACE_OFFSET - 4, 0), sandColor, Enum.Material.Sand)
	-- Зелёная лужайка в центре острова (площадь "городка"): нижняя грань чуть выше
	-- песка, чтобы не было копланарных граней.
	makeCylinder(folder, "TownLawn", 0.3, sandRadius, position + Vector3.new(0, SURFACE_OFFSET + 0.2, 0), Color3.fromRGB(118, 178, 92), Enum.Material.Grass)

	return sand, sandRadius
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

-- Расставляет пальмы и камни по песчаному кольцу острова, обходя зону ракетных
-- стендов (северная полоса), точку спавна и центр-лужайку.
local function buildIslandDecor(parent, position, plotId)
	local decor = Instance.new("Folder")
	decor.Name = "IslandDecor"
	decor.Parent = parent

	local spawnPos = position + Vector3.new(0, SURFACE_OFFSET, 40)

	local target = 8 + (plotId % 3) -- 8..10 пальм на остров
	local placed, attempts = 0, 0
	while placed < target and attempts < 80 do
		attempts += 1
		local ang = math.random() * math.pi * 2
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local radius = 55 + math.random() * 34
		local pos = position + dir * radius + Vector3.new(0, SURFACE_OFFSET, 0)

		local dx = pos.X - position.X
		local dz = pos.Z - position.Z
		-- Полоса ракетных стендов и зелёных кругов: не сажаем пальмы внутрь.
		local inLauncherZone = dz > -44 and dz < -8 and math.abs(dx) < 56
		if not inLauncherZone and (pos - spawnPos).Magnitude > 14 then
			buildPalm(decor, pos, math.deg(ang) + math.random(-40, 40), 0.85 + math.random() * 0.55)
			placed += 1
		end
	end

	-- Прибрежные камни (наполовину в песке)
	for index, offset in ipairs({ Vector3.new(86, SURFACE_OFFSET - 1, -38), Vector3.new(-84, SURFACE_OFFSET - 1, 20), Vector3.new(34, SURFACE_OFFSET - 1, 84), Vector3.new(-26, SURFACE_OFFSET - 1, -80) }) do
		local rock = makePart(decor, "BeachRock_" .. index, Vector3.new(5 + index, 3 + index % 2, 5 + index), CFrame.new(position + offset), Color3.fromRGB(111, 105, 91), Enum.Material.Rock)
		rock.Shape = Enum.PartType.Ball
	end
end

-- === Ракеты четырёх поколений (Mark I..IV) ===
-- Ракеты v3 стали ШИРЕ и ВЫШЕ; каждые 5 уровней прокачки стенд перестраивается
-- в следующий Mark (см. Config.RocketMark + PlotManager.RebuildLauncher).
local MARK_SPECS = {
	[1] = { -- классическая белая ракета
		dia = 4.6, bodyH = 15, noseH = 4.5, finH = 6.4, boosters = 0, rings = 0,
		bodyColor = Color3.fromRGB(236, 239, 241), bodyMat = Enum.Material.SmoothPlastic,
	},
	[2] = { -- с двумя боковыми ускорителями
		dia = 5.0, bodyH = 18, noseH = 5.2, finH = 7.2, boosters = 2, rings = 1,
		bodyColor = Color3.fromRGB(240, 243, 244), bodyMat = Enum.Material.SmoothPlastic,
	},
	[3] = { -- тяжёлая тёмная с неоновыми кольцами
		dia = 5.6, bodyH = 21, noseH = 5.8, finH = 8, boosters = 0, rings = 3,
		bodyColor = Color3.fromRGB(60, 64, 72), bodyMat = Enum.Material.Metal, dark = true,
	},
	[4] = { -- флагман: три ускорителя, золотой нос и неоновое гало
		dia = 6.0, bodyH = 23, noseH = 6.4, finH = 9, boosters = 3, rings = 2,
		bodyColor = Color3.fromRGB(245, 246, 248), bodyMat = Enum.Material.SmoothPlastic,
		goldAccent = true, halo = true,
	},
}

-- Строит ракету поколения mark над basePos (уровень песка). Возвращает список
-- частей (для скрытия на перезарядке), иллюминатор и точку вылета (нос).
local function buildRocketModel(model, basePos, teamColor, mark)
	local spec = MARK_SPECS[mark] or MARK_SPECS[1]
	local accent = spec.goldAccent and Color3.fromRGB(255, 199, 70) or teamColor
	local parts = {}
	local function reg(part)
		part.CanCollide = false
		table.insert(parts, part)
		return part
	end

	local bottomY = basePos.Y + 0.65 -- верх бетонной площадки

	-- Двигательный отсек: сопло, юбка и тёплое свечение
	reg(makeCylinder(model, "Nozzle", 2.2, spec.dia * 0.62, Vector3.new(basePos.X, bottomY + 1.1, basePos.Z), Color3.fromRGB(40, 42, 46), Enum.Material.Metal))
	reg(makeCylinder(model, "Skirt", 1.6, spec.dia * 0.92, Vector3.new(basePos.X, bottomY + 2.6, basePos.Z), Color3.fromRGB(70, 74, 80), Enum.Material.Metal))
	reg(makeCylinder(model, "EngineGlow", 0.5, spec.dia * 0.5, Vector3.new(basePos.X, bottomY + 0.35, basePos.Z), Color3.fromRGB(255, 170, 60), Enum.Material.Neon))

	-- Корпус
	local bodyH = spec.bodyH
	local bodyCenterY = bottomY + 3.4 + bodyH / 2
	local body = makeCylinder(model, "Body", bodyH, spec.dia, Vector3.new(basePos.X, bodyCenterY, basePos.Z), spec.bodyColor, spec.bodyMat)
	table.insert(parts, body)

	-- Полоса команды + неоновые кольца прокачанных версий
	reg(makeCylinder(model, "Stripe", 2.0, spec.dia * 1.04, Vector3.new(basePos.X, bodyCenterY + bodyH * 0.18, basePos.Z), accent, Enum.Material.SmoothPlastic))
	for r = 1, (spec.rings or 0) do
		local ringY = bodyCenterY - bodyH / 2 + bodyH * r / (spec.rings + 1)
		reg(makeCylinder(model, "Ring_" .. r, 0.7, spec.dia * 1.06, Vector3.new(basePos.X, ringY, basePos.Z), spec.dark and teamColor or accent, Enum.Material.Neon))
	end

	-- Иллюминатор смотрит на центр острова (+Z от стенда)
	local window = makePart(model, "Window", Vector3.new(0.5, 1.6, 1.6), CFrame.new(Vector3.new(basePos.X, bodyCenterY + bodyH * 0.32, basePos.Z + spec.dia / 2 + 0.05)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(125, 214, 238), Enum.Material.Glass)
	window.Shape = Enum.PartType.Cylinder
	window.CanCollide = false

	-- Конусообразный нос из сужающихся секций + шпиль
	local noseBottom = bodyCenterY + bodyH / 2
	local noseSegs = 5
	for i = 1, noseSegs do
		local d = spec.dia * (1 - (i / noseSegs) * 0.82)
		local segH = spec.noseH / noseSegs
		reg(makeCylinder(model, "Nose_" .. i, segH, math.max(d, 0.6), Vector3.new(basePos.X, noseBottom + (i - 0.5) * segH, basePos.Z), accent, Enum.Material.SmoothPlastic))
	end
	local tipY = noseBottom + spec.noseH
	reg(makePart(model, "Tip", Vector3.new(0.5, 2.2, 0.5), CFrame.new(Vector3.new(basePos.X, tipY + 0.9, basePos.Z)), Color3.fromRGB(226, 228, 232), Enum.Material.Metal))

	-- Неоновое гало флагмана
	if spec.halo then
		local halo = makeCylinder(model, "Halo", 0.4, spec.dia + 3, Vector3.new(basePos.X, tipY - 1, basePos.Z), accent, Enum.Material.Neon)
		halo.Transparency = 0.3
		reg(halo)
	end

	-- Боковые ускорители
	if (spec.boosters or 0) > 0 then
		local boosterD = spec.dia * 0.36
		local boosterH = bodyH * 0.55
		for i = 1, spec.boosters do
			local a = math.rad(360 / spec.boosters * i + 90)
			local bx = basePos.X + math.cos(a) * (spec.dia / 2 + boosterD / 2 + 0.1)
			local bz = basePos.Z + math.sin(a) * (spec.dia / 2 + boosterD / 2 + 0.1)
			reg(makeCylinder(model, "Booster_" .. i, boosterH, boosterD, Vector3.new(bx, bottomY + 2.0 + boosterH / 2, bz), spec.bodyColor, spec.bodyMat))
			reg(makeCylinder(model, "BoosterNose_" .. i, 1.4, boosterD * 0.55, Vector3.new(bx, bottomY + 2.0 + boosterH + 0.7, bz), accent, Enum.Material.SmoothPlastic))
		end
	end

	-- Стабилизаторы
	for i = 1, 4 do
		local a = math.rad(i * 90 + 45)
		local dist = spec.dia / 2 + 0.9
		local finPos = Vector3.new(basePos.X + math.cos(a) * dist, bottomY + spec.finH / 2 + 0.4, basePos.Z + math.sin(a) * dist)
		local fin = makeWedge(model, "Fin_" .. i, Vector3.new(0.7, spec.finH, 3.6), CFrame.new(finPos) * CFrame.Angles(0, -a + math.rad(90), 0), accent, Enum.Material.SmoothPlastic)
		fin.CanCollide = false
		table.insert(parts, fin)
	end

	local origin = Vector3.new(basePos.X, tipY + 2, basePos.Z)
	return parts, window, origin
end

local function buildIslandModel(plotId, position)
	local folder = Instance.new("Folder")
	folder.Name = "Plot_" .. plotId
	folder:SetAttribute("PlotId", plotId)
	folder:SetAttribute("OwnerUserId", 0)
	folder.Parent = workspace

	local themeColor = PLOT_THEME_COLORS[plotId] or Color3.fromRGB(150, 150, 150)

	-- Единые сплошные цилиндры вместо перекрывающихся сегментов (устраняет z-fighting песка).
	buildIslandBase(folder, position, Color3.fromRGB(235, 211, 149))
	buildIslandDecor(folder, position, plotId)

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
		-- (PriceTags) — ценники показываются ТОЛЬКО на своём острове. Атрибут
		-- Unlocked отражает, открыт ли слот (последовательное открытие слотов).
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "PriceTag"
		billboard.Size = UDim2.new(0, 150, 0, 44)
		billboard.StudsOffset = Vector3.new(0, 5, 0)
		billboard.AlwaysOnTop = true
		billboard.Enabled = false
		billboard:SetAttribute("Unlocked", slotIdx == 1)
		billboard.Parent = buyPad

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "PriceLabel"
		priceLabel.Size = UDim2.new(1, 0, 1, 0)
		priceLabel.BackgroundTransparency = 1
		priceLabel.TextScaled = false
		priceLabel.TextSize = 15
		priceLabel.Font = Enum.Font.GothamMedium
		priceLabel.TextColor3 = Color3.fromRGB(240, 244, 246)
		priceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		priceLabel.TextStrokeTransparency = 0.5
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
		label.TextSize = 15
		label.Font = Enum.Font.GothamMedium
		label.TextColor3 = Color3.fromRGB(240, 244, 246)
		label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		label.TextStrokeTransparency = 0.5
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

	local parts, window, origin = buildRocketModel(model, basePos, teamColor, mark)

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
