-- PlotManager.luau - ocean world, sandy islands, wildlife, and launchers

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)
local Config            = require(sharedFolder:WaitForChild("Config"))

local PlotManager = {}

local plots = {}
local playerPlot = {}

local PLOT_THEME_COLORS = {
	Color3.fromRGB(46, 117, 224),
	Color3.fromRGB(224, 76, 46),
	Color3.fromRGB(46, 200, 90),
	Color3.fromRGB(230, 180, 30),
	Color3.fromRGB(170, 50, 230),
	Color3.fromRGB(40, 210, 210),
}

-- Высота ходибельной песчаной поверхности острова над Y центра плота.
-- Все объекты (спавн, кнопки, ракеты, пальмы) выравниваются по этой высоте.
local ISLAND_SURFACE_OFFSET = 10

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

-- Вертикальный сплошной цилиндр-диск (ось цилиндра направлена вверх по Y).
-- Слои острова делаем сплошными непересекающимися дисками — это убирает
-- z-fighting «плывущего песка», который был из-за десятков наложенных партов.
local function makeDisc(parent, name, radius, thickness, centerY, worldXZ, color, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(thickness, radius * 2, radius * 2)
	-- ось цилиндра (локальный X) поворачиваем в вертикаль
	part.CFrame = CFrame.new(worldXZ.X, centerY, worldXZ.Z) * CFrame.Angles(0, 0, math.rad(90))
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

	local radius = 120 + (index % 3) * 55
	local angle = index / 10 * math.pi * 2
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
	terrain.WaterColor = Color3.fromRGB(20, 126, 171)
	terrain.WaterTransparency = 0.18
	terrain.WaterReflectance = 0.38
	terrain.WaterWaveSize = 0.35
	terrain.WaterWaveSpeed = 9

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

	local world = Instance.new("Folder")
	world.Name = "OceanWildlife"
	world.Parent = workspace
	for index = 1, 14 do
		buildShark(world, index)
	end
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

-- Высота верхней грани песка над position.Y. Общая точка отсчёта для спавна,
-- кнопок, ракет и пальм, чтобы всё стояло ровно на поверхности.
local SURFACE_OFFSET = 10

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

-- Расставляет пальмы и камни по острову, обходя центр (ракеты), направления слотов
-- (кнопки/мосты) и точку спавна.
local function buildIslandDecor(parent, position, plotId, isCentral)
	local decor = Instance.new("Folder")
	decor.Name = "IslandDecor"
	decor.Parent = parent

	local slotDirs = {}
	if not isCentral then
		for _, off in pairs(Config.SLOT_OFFSETS) do
			table.insert(slotDirs, off.Unit)
		end
	end
	local spawnPos = position + Vector3.new(-14, SURFACE_OFFSET, -18)

	local target = isCentral and 8 or (6 + (plotId % 3)) -- 6..8 пальм на остров
	local placed, attempts = 0, 0
	while placed < target and attempts < 60 do
		attempts += 1
		local ang = math.random() * math.pi * 2
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))

		local blocked = false
		for _, sd in ipairs(slotDirs) do
			if dir:Dot(sd) > math.cos(math.rad(24)) then
				blocked = true
				break
			end
		end
		if not blocked then
			local radius = (isCentral and 24 or 40) + math.random() * 16
			local pos = position + dir * radius + Vector3.new(0, SURFACE_OFFSET, 0)
			if (pos - spawnPos).Magnitude > 14 then
				buildPalm(decor, pos, math.deg(ang) + math.random(-40, 40), 0.85 + math.random() * 0.55)
				placed += 1
			end
		end
	end

	-- Прибрежные камни (наполовину в песке)
	for index, offset in ipairs({ Vector3.new(48, SURFACE_OFFSET - 1, -24), Vector3.new(-46, SURFACE_OFFSET - 1, 8), Vector3.new(18, SURFACE_OFFSET - 1, 47), Vector3.new(-12, SURFACE_OFFSET - 1, -47) }) do
		local rock = makePart(decor, "BeachRock_" .. index, Vector3.new(4 + index, 3 + index % 2, 4 + index), CFrame.new(position + offset), Color3.fromRGB(111, 105, 91), Enum.Material.Rock)
		rock.Shape = Enum.PartType.Ball
	end
end

-- Центральный остров закрывает "дырку" в самом центре карты (world origin).
local function buildCentralIsland()
	local old = workspace:FindFirstChild("CentralIsland")
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name = "CentralIsland"
	folder.Parent = workspace
	local position = Vector3.new(0, Config.PLOT_POSITIONS[1].Y, 0)

	buildIslandBase(folder, position, Color3.fromRGB(238, 216, 158))
	buildIslandDecor(folder, position, 0, true)

	-- Скала-ориентир по центру
	local rock = makePart(folder, "CenterRock", Vector3.new(18, 30, 18), CFrame.new(position + Vector3.new(0, SURFACE_OFFSET + 15, 0)), Color3.fromRGB(96, 92, 80), Enum.Material.Rock)
	rock.Shape = Enum.PartType.Ball
	local peak = makePart(folder, "CenterPeak", Vector3.new(9, 16, 9), CFrame.new(position + Vector3.new(0, SURFACE_OFFSET + 30, 0)), Color3.fromRGB(108, 104, 92), Enum.Material.Rock)
	peak.Shape = Enum.PartType.Ball
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
	buildIslandDecor(folder, position, plotId, false)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlotSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = position + Vector3.new(-14, 10.5, -18)
	spawn.Color = Color3.fromRGB(245, 223, 163)
	spawn.Material = Enum.Material.Sand
	spawn.Neutral = false
	spawn.Duration = 0
	spawn.Parent = folder

	-- Launcher models are added here as the player expands from one to six.
	local siloFolder = Instance.new("Folder")
	siloFolder.Name = "RocketSilo"
	siloFolder.Parent = folder

	-- Кнопки покупки — плоские зелёные "блины" на песке. Покупка/прокачка срабатывает
	-- по НАСТУПАНИЮ (Touched), без ProximityPrompt. Над каждой висит ценник (BillboardGui).
	local slotsData = {}
	for slotIdx, offset in ipairs(Config.SLOT_OFFSETS) do
		local dir = offset.Unit
		local edgePos = position + dir * ((Config.PLOT_CENTER_SIZE / 2) - 14)

		local buyPad = Instance.new("Part")
		buyPad.Name = "BuyPad_" .. slotIdx
		buyPad.Shape = Enum.PartType.Cylinder
		buyPad.Anchored = true
		buyPad.Size = Vector3.new(0.6, 8, 8)
		buyPad.Orientation = Vector3.new(0, 0, 90)
		buyPad.Position = edgePos + Vector3.new(0, SURFACE_OFFSET + 0.3, 0)
		buyPad.Color = Color3.fromRGB(69, 200, 110)
		buyPad.Material = Enum.Material.Neon
		if slotIdx > 1 then
			-- Заблокированные слоты скрыты до постройки предыдущего.
			buyPad.Transparency = 1
			buyPad.CanCollide = false
		end
		buyPad.Parent = folder

		-- Ценник над кнопкой
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "PriceTag"
		billboard.Size = UDim2.new(0, 210, 0, 58)
		billboard.StudsOffset = Vector3.new(0, 6, 0)
		billboard.AlwaysOnTop = true
		billboard.Enabled = slotIdx == 1
		billboard.Parent = buyPad

		local priceLabel = Instance.new("TextLabel")
		priceLabel.Name = "PriceLabel"
		priceLabel.Size = UDim2.new(1, 0, 1, 0)
		priceLabel.BackgroundTransparency = 1
		priceLabel.TextScaled = true
		priceLabel.Font = Enum.Font.GothamBold
		priceLabel.TextColor3 = Color3.fromRGB(190, 255, 200)
		priceLabel.TextStrokeColor3 = Color3.fromRGB(0, 45, 10)
		priceLabel.TextStrokeTransparency = 0.4
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

	plots[plotId] = {
		owner = nil,
		folder = folder,
		center = position,
		spawn = spawn,
		slots = slotsData,
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
	buildOcean()

	-- Закрываем "дырку" в центре карты центральным островом.
	buildCentralIsland()

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
			end
			playerPlot[player] = nil
		end
	end)
end

function PlotManager.CreateLauncher(player, launcherIndex)
	local _, plot = PlotManager.GetPlotByPlayer(player)
	if not plot or plot.launchers[launcherIndex] then return plot and plot.launchers[launcherIndex] end
	local offset = Config.LAUNCHER_OFFSETS[launcherIndex]
	if not offset then return nil end

	local model = Instance.new("Model")
	model.Name = "Launcher_" .. launcherIndex
	model:SetAttribute("LauncherIndex", launcherIndex)
	model.Parent = plot.folder:FindFirstChild("RocketSilo")

	local teamColor = plot.themeColor
	-- Ракета СТОИТ на песке: считаем уровень песка и ставим на него бетонную площадку.
	local sandY = plot.center.Y + SURFACE_OFFSET
	local basePos = Vector3.new(plot.center.X + offset.X, sandY, plot.center.Z + offset.Z)

	-- Бетонная площадка ~0.3 studs, лежащая на песке
	local pad = makeCylinder(model, "Pad", 0.3, 9, basePos + Vector3.new(0, 0.15, 0), Color3.fromRGB(150, 150, 155), Enum.Material.Concrete)
	local rim = makeCylinder(model, "ReadyRim", 0.5, 10, basePos + Vector3.new(0, 0.35, 0), teamColor, Enum.Material.Neon)
	rim.CanCollide = false

	local bottomY = sandY + 0.3
	local parts = {}

	-- Сопло (тёмный цилиндр снизу)
	local nozzle = makeCylinder(model, "Nozzle", 1.6, 2.1, Vector3.new(basePos.X, bottomY + 0.8, basePos.Z), Color3.fromRGB(45, 45, 50), Enum.Material.Metal)
	nozzle.CanCollide = false
	table.insert(parts, nozzle)

	-- Корпус (высота ~11, диаметр 3)
	local bodyH = 11
	local bodyCenterY = bottomY + 1.4 + bodyH / 2
	local body = makeCylinder(model, "Body", bodyH, 3, Vector3.new(basePos.X, bodyCenterY, basePos.Z), Color3.fromRGB(232, 236, 238), Enum.Material.SmoothPlastic)
	table.insert(parts, body)

	-- Полоса цвета команды
	local stripe = makeCylinder(model, "Stripe", 1.6, 3.12, Vector3.new(basePos.X, bodyCenterY + 1.6, basePos.Z), teamColor, Enum.Material.SmoothPlastic)
	stripe.CanCollide = false
	table.insert(parts, stripe)

	-- Иллюминатор (маленький круглый парт на корпусе)
	local window = makePart(model, "Window", Vector3.new(0.4, 1.1, 1.1), CFrame.new(Vector3.new(basePos.X, bodyCenterY + 3, basePos.Z - 1.55)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(120, 210, 235), Enum.Material.Glass)
	window.Shape = Enum.PartType.Cylinder
	window.CanCollide = false

	-- Конусообразный нос (сборка из сужающихся цилиндров)
	local noseBottom = bodyCenterY + bodyH / 2
	for i = 1, 4 do
		local d = 3 * (1 - i * 0.2)
		local nc = makeCylinder(model, "Nose_" .. i, 1.0, math.max(d, 0.4), Vector3.new(basePos.X, noseBottom + (i - 0.5) * 1.0, basePos.Z), teamColor, Enum.Material.SmoothPlastic)
		nc.CanCollide = false
		table.insert(parts, nc)
	end
	local origin = Vector3.new(basePos.X, noseBottom + 4.0, basePos.Z)

	-- 4 стабилизатора-плавника внизу (клинья)
	for i = 1, 4 do
		local a = math.rad(i * 90)
		local finPos = Vector3.new(basePos.X + math.cos(a) * 1.8, bottomY + 1.9, basePos.Z + math.sin(a) * 1.8)
		local fin = makeWedge(model, "Fin_" .. i, Vector3.new(0.4, 3.4, 2.8), CFrame.new(finPos) * CFrame.Angles(0, -a + math.rad(90), 0), teamColor, Enum.Material.SmoothPlastic)
		fin.CanCollide = false
		table.insert(parts, fin)
	end

	-- ProximityPrompt "Запустить" (зажать E)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "LaunchPrompt"
	prompt.ActionText = Config.LAUNCH_PROMPT_ACTION
	prompt.ObjectText = "Ракета " .. launcherIndex
	prompt.HoldDuration = Config.LAUNCH_PROMPT_HOLD
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = body

	model.PrimaryPart = pad
	plot.launchers[launcherIndex] = { model = model, parts = parts, window = window, rim = rim, prompt = prompt, origin = origin }
	return plot.launchers[launcherIndex]
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
	if launcher.prompt then launcher.prompt.Enabled = ready end
end

function PlotManager.GetLauncherOrigin(player, launcherIndex)
	local _, plot = PlotManager.GetPlotByPlayer(player)
	local launcher = plot and plot.launchers[launcherIndex]
	return launcher and launcher.origin
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