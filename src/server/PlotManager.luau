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

local ISLAND_PATTERNS = {
	{ Vector2.new(-0.52, -0.18), Vector2.new(-0.35, -0.58), Vector2.new(0.14, -0.65), Vector2.new(0.62, -0.28), Vector2.new(0.52, 0.31), Vector2.new(0.12, 0.57), Vector2.new(-0.46, 0.45), Vector2.new(-0.68, 0.08) },
	{ Vector2.new(-0.62, -0.08), Vector2.new(-0.27, -0.52), Vector2.new(0.32, -0.46), Vector2.new(0.67, -0.05), Vector2.new(0.35, 0.56), Vector2.new(-0.22, 0.62), Vector2.new(-0.6, 0.32) },
	{ Vector2.new(-0.58, -0.35), Vector2.new(-0.08, -0.66), Vector2.new(0.5, -0.45), Vector2.new(0.63, 0.2), Vector2.new(0.25, 0.63), Vector2.new(-0.35, 0.52), Vector2.new(-0.67, 0.15) },
	{ Vector2.new(-0.68, -0.12), Vector2.new(-0.35, -0.6), Vector2.new(0.2, -0.55), Vector2.new(0.63, -0.18), Vector2.new(0.58, 0.38), Vector2.new(0.02, 0.61), Vector2.new(-0.55, 0.4) },
}

local function makeIslandLayer(parent, name, position, points, y, thickness, scale, color, material)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local hub = makePart(model, "Hub", Vector3.new(2, thickness, 2), CFrame.new(position + Vector3.new(0, y, 0)), color, material)
	hub.Transparency = 1
	hub.CanCollide = false
	model.PrimaryPart = hub

	for index, point in ipairs(points) do
		local nextPoint = points[index % #points + 1]
		local a = position + Vector3.new(point.X * scale, y, point.Y * scale)
		local b = position + Vector3.new(nextPoint.X * scale, y, nextPoint.Y * scale)
		local segment = b - a
		local length = segment.Magnitude
		local part = makePart(model, "Shore_" .. index, Vector3.new(scale * 0.78, thickness, length + scale * 0.28), CFrame.lookAt((a + b) / 2, b), color, material)
		part.Orientation = Vector3.new(0, part.Orientation.Y, 0)
	end
	return model
end

local function buildIslandDecor(parent, position, plotId)
	local decor = Instance.new("Folder")
	decor.Name = "IslandDecor"
	decor.Parent = parent
	local rotation = (plotId * 37) % 360

	for index, offset in ipairs({ Vector3.new(-34, 10, 28), Vector3.new(36, 10, 20), Vector3.new(-28, 10, -30) }) do
		local trunk = makePart(decor, "PalmTrunk_" .. index, Vector3.new(1.4, 14, 1.4), CFrame.new(position + offset + Vector3.new(0, 7, 0)) * CFrame.Angles(math.rad(index * 4), 0, math.rad(index * 3)), Color3.fromRGB(111, 77, 43), Enum.Material.Wood)
		for leaf = 1, 6 do
			local angle = math.rad(rotation + leaf * 60)
			local leafPart = makePart(decor, "PalmLeaf", Vector3.new(2.2, 0.35, 11), CFrame.new(trunk.Position + Vector3.new(0, 7, 0)) * CFrame.Angles(math.rad(20), angle, 0) * CFrame.new(0, 0, -4), Color3.fromRGB(53, 127, 71), Enum.Material.Grass)
			leafPart.CanCollide = false
		end
	end

	for index, offset in ipairs({ Vector3.new(43, 9, -22), Vector3.new(-42, 9, 6), Vector3.new(17, 9, 42), Vector3.new(-10, 9, -43) }) do
		local rock = makePart(decor, "BeachRock_" .. index, Vector3.new(4 + index, 3 + index % 2, 4 + index), CFrame.new(position + offset), Color3.fromRGB(111, 105, 91), Enum.Material.Rock)
		rock.Shape = Enum.PartType.Ball
	end
end

local function buildIslandModel(plotId, position)
	local folder = Instance.new("Folder")
	folder.Name = "Plot_" .. plotId
	folder:SetAttribute("PlotId", plotId)
	folder:SetAttribute("OwnerUserId", 0)
	folder.Parent = workspace

	local themeColor = PLOT_THEME_COLORS[plotId] or Color3.fromRGB(150, 150, 150)
	local pattern = ISLAND_PATTERNS[(plotId - 1) % #ISLAND_PATTERNS + 1]
	local shoreScale = Config.PLOT_CENTER_SIZE

	-- Three stacked, offset coast layers make each island read as sand over rock,
	-- rather than a perfectly circular platform.
	makeIslandLayer(folder, "SubmergedReef", position, pattern, -21, 18, shoreScale * 1.16, Color3.fromRGB(52, 73, 78), Enum.Material.Slate)
	makeIslandLayer(folder, "RockShelf", position, pattern, -5, 16, shoreScale * 1.04, Color3.fromRGB(92, 87, 75), Enum.Material.Rock)
	makeIslandLayer(folder, "SandShore", position, pattern, 6, 8, shoreScale, Color3.fromRGB(235, 211, 149), Enum.Material.Sand)
	buildIslandDecor(folder, position, plotId)

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

	-- Purchase pads are inset into the beach so the island stays a coherent space.
	local slotsData = {}
	for slotIdx, offset in ipairs(Config.SLOT_OFFSETS) do
		local dir = offset.Unit
		local edgePos = position + dir * ((Config.PLOT_CENTER_SIZE / 2) - 14)

		local buyPad = Instance.new("Part")
		buyPad.Name = "BuyPad_" .. slotIdx
		buyPad.Shape = Enum.PartType.Cylinder
		buyPad.Anchored = true
		buyPad.Size = Vector3.new(0.45, 7, 7)
		buyPad.Orientation = Vector3.new(0, 0, 90)
		buyPad.Position = edgePos + Vector3.new(0, 10.25, 0)
		buyPad.Color = Color3.fromRGB(69, 160, 99)
		buyPad.Material = Enum.Material.SmoothPlastic
		if slotIdx > 1 then
			buyPad.Transparency = 1
			buyPad.CanCollide = false
		end
		buyPad.Parent = folder

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "BuyPrompt"
		prompt.ActionText = "Построить"
		prompt.ObjectText = ""
		prompt.HoldDuration = 0.25
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Enabled = slotIdx == 1
		prompt.Parent = buyPad

		slotsData[slotIdx] = {
			center = position + offset,
			edgePos = edgePos,
			buyPad = buyPad,
			buyPrompt = prompt,
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
	local position = plot.center + offset + Vector3.new(0, 14, 0)
	local base = makePart(model, "Base", Vector3.new(12, 2, 12), CFrame.new(position), Color3.fromRGB(52, 60, 67), Enum.Material.DiamondPlate)
	local rim = makePart(model, "ReadyRim", Vector3.new(1, 10, 10), CFrame.new(position + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), plot.themeColor, Enum.Material.Neon)
	rim.Shape = Enum.PartType.Cylinder
	rim.CanCollide = false
	local rocket = makePart(model, "Rocket", Vector3.new(12, 3.2, 3.2), CFrame.new(position + Vector3.new(0, 7.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(224, 230, 232), Enum.Material.Metal)
	rocket.Shape = Enum.PartType.Cylinder
	local nose = makePart(model, "Nose", Vector3.new(3.5, 3.5, 3.5), CFrame.new(position + Vector3.new(0, 14.5, 0)), plot.themeColor, Enum.Material.Neon)
	nose.Shape = Enum.PartType.Ball
	nose.CanCollide = false
	model.PrimaryPart = base
	plot.launchers[launcherIndex] = { model = model, rocket = rocket, nose = nose, rim = rim, origin = nose.Position }
	return plot.launchers[launcherIndex]
end

function PlotManager.SetLauncherReady(player, launcherIndex, ready)
	local _, plot = PlotManager.GetPlotByPlayer(player)
	local launcher = plot and plot.launchers[launcherIndex]
	if not launcher then return end
	launcher.rocket.Transparency = ready and 0 or 1
	launcher.nose.Transparency = ready and 0 or 1
	launcher.rim.Color = ready and plot.themeColor or Color3.fromRGB(85, 91, 95)
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