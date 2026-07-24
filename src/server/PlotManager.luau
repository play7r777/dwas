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

-- === АКУЛЫ ===
-- Акула плавает ПОД водой по своему кольцу вокруг пустого центра карты и
-- периодически всплывает так, что над поверхностью видно ТОЛЬКО спинной плавник.
-- Если рядом ПЛЫВЁТ игрок — акула сворачивает с кольца, догоняет и ГРЫЗЁТ:
-- Config.SHARKS.DPS урона в секунду (одна акула съедает игрока за 20 секунд —
-- скорее декорация с зубами, чем настоящий хищник; вышел из воды — отстала).
-- Внешний вид: меш assets/shark (ReplicatedStorage/SharkMeshes/shark или общая
-- папка Meshes). Пока меша нет — процедурная акула из партов (крупнее прежней).

-- Ближайший игрок В ВОДЕ (голова ниже уровня воды + запас) в радиусе агро.
local function findPrey(pos)
	local best, bestDist
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and hrp.Position.Y < Config.WATER_LEVEL + 1 then
			local d = (hrp.Position - pos).Magnitude
			if d <= Config.SHARKS.AGGRO_RADIUS and (not bestDist or d < bestDist) then
				best, bestDist = hrp, d
			end
		end
	end
	return best
end

local function buildShark(parent, index)
	local cfg = Config.SHARKS
	local model = Instance.new("Model")
	model.Name = "Shark_" .. index
	model.Parent = parent

	-- Невидимый корень: PivotTo двигает всю модель, нос смотрит по -Z корня.
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.5, 0.5, 0.5)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	local tail -- только у процедурного фолбэка (виляет отдельно)
	local meshPart = MeshLibrary.FindPart(cfg.FOLDER, cfg.FILES)
	if meshPart then
		-- Меш из assets/shark: длина зашита вдоль X, масштабируем по длинной оси.
		local long = math.max(meshPart.Size.X, meshPart.Size.Z, 0.001)
		meshPart.Name = "Body"
		meshPart.Size = meshPart.Size * (cfg.LENGTH / long)
		meshPart.Anchored = true
		meshPart.CanCollide = false
		meshPart.CanQuery = false
		-- Нос меша (-X) доворачиваем вперёд по движению (-Z корня).
		meshPart.CFrame = root.CFrame * CFrame.Angles(0, math.rad(cfg.MESH_YAW), 0)
		meshPart.Parent = model
	else
		-- Фолбэк: акула из партов, в ~1.25 раза крупнее прежней.
		local body = makePart(model, "Body", Vector3.new(5, 5, 16), root.CFrame, Color3.fromRGB(67, 88, 101), Enum.Material.SmoothPlastic)
		body.Shape = Enum.PartType.Ball
		body.CanCollide = false
		body.CanQuery = false
		local fin = makePart(model, "Fin", Vector3.new(0.8, 6, 6), root.CFrame * CFrame.new(0, 3.7, 1.2) * CFrame.Angles(0, 0, math.rad(45)), body.Color, Enum.Material.SmoothPlastic)
		fin.CanCollide = false
		fin.CanQuery = false
		tail = makePart(model, "Tail", Vector3.new(1, 8.5, 6), root.CFrame * CFrame.new(0, 0, 8.6), body.Color, Enum.Material.SmoothPlastic)
		tail.CanCollide = false
		tail.CanQuery = false
	end

	task.spawn(function()
		-- Центр карты — пустая вода: акулы кружат именно там, каждая на своём кольце.
		local radius = 130 + (index % 4) * 70
		local angle = index / cfg.COUNT * math.pi * 2
		local phase = index * 1.3
		local pos = Vector3.new(math.cos(angle) * radius, Config.WATER_LEVEL - 8, math.sin(angle) * radius)
		local clock = phase
		local biteAccum = 0
		local hunting = false

		-- Глубина «дышит» синусом: от -12.6 (глубоко) до -2.6 (у поверхности) —
		-- на пике всплытия наружу торчит только спинной плавник.
		local function wanderY(tt)
			return (Config.WATER_LEVEL - 2.6) - (math.sin(tt * 0.9 + phase) + 1) * 5
		end

		while model.Parent do
			local dt = task.wait(0.05)
			clock += dt

			local prey = findPrey(pos)
			local targetPos, speed
			if prey then
				hunting = true
				-- Грызём снизу: цель чуть под игроком, но не выше «наружу только плавник».
				local py = math.clamp(prey.Position.Y - 1, Config.SEABED_LEVEL + 6, Config.WATER_LEVEL - 2)
				targetPos = Vector3.new(prey.Position.X, py, prey.Position.Z)
				speed = cfg.HUNT_SPEED
			else
				if hunting then
					-- Погоня кончилась: пересинхронизируем кольцо с текущей точкой,
					-- чтобы акула плавно вернулась на маршрут без телепорта.
					hunting = false
					angle = math.atan2(pos.Z, pos.X)
				end
				angle += (cfg.SWIM_SPEED / radius) * dt
				targetPos = Vector3.new(math.cos(angle) * radius, wanderY(clock), math.sin(angle) * radius)
				speed = cfg.SWIM_SPEED * 1.6 -- запас, чтобы не отставать от точки на кольце
			end

			local delta = targetPos - pos
			local dist = delta.Magnitude
			if dist > 0.05 then
				local step = math.min(dist, speed * dt)
				local dir = delta / dist
				pos += dir * step
				-- Наклон по вертикали приглушаем: акула не «клюёт носом».
				model:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(dir.X, dir.Y * 0.6, dir.Z)))
			end
			if tail then
				tail.CFrame = root.CFrame * CFrame.new(0, 0, 8.6) * CFrame.Angles(0, math.sin(clock * 6) * 0.25, 0)
			end

			-- Укус: всем, кто В ВОДЕ и в радиусе укуса, тикает маленький урон.
			biteAccum += dt
			if biteAccum >= cfg.BITE_TICK then
				biteAccum = 0
				for _, player in ipairs(Players:GetPlayers()) do
					local char = player.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					local hum = char and char:FindFirstChildOfClass("Humanoid")
					if hrp and hum and hum.Health > 0
						and hrp.Position.Y < Config.WATER_LEVEL + 1
						and (hrp.Position - pos).Magnitude <= cfg.BITE_RADIUS then
						hum:TakeDamage(cfg.DPS * cfg.BITE_TICK)
					end
				end
			end
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
	for index = 1, Config.SHARKS.COUNT do
		buildShark(world, index)
	end
end

-- Остров. Если в ReplicatedStorage лежит ЛЕГО-МЕШ из Blender
-- (IslandMeshes/MainIsland, см. assets/island/main_island.py) — используем его:
-- зелёная стад-плита, дорога с пунктиром, газон и зона ракет с чёрно-жёлтой
-- лентой. Иначе фолбэк: вложенные сплошные цилиндры (никаких перекрывающихся
-- копланарных партов → нет "дрожащего песка"/z-fighting).
-- ПРИОРИТЕТНЫЙ путь: остров из ОТДЕЛЬНЫХ однотонных деталей (island_grass,
-- island_road, ... — см. assets/island/export_parts.py). Без текстур — нечему
-- зависать в обработке Roblox; собирается по смещениям из Config.ISLAND.PIECES.
local function tryBuildIslandPieces(folder, position)
	local pc = Config.ISLAND.PIECES
	local s = Config.ISLAND.MAIN_WIDTH / pc.FULL_WIDTH
	local baseCF = CFrame.new(position.X, position.Y + SURFACE_OFFSET - pc.WALK_TOP * s, position.Z)
		* CFrame.Angles(0, math.rad(Config.ISLAND.YAW), 0)
	local model, count = MeshLibrary.AssemblePieces(Config.ISLAND.FOLDER, pc, baseCF, Config.ISLAND.MAIN_WIDTH, "MainIsland")
	if not model then return nil end
	-- Детали и так однотонные; страховка докрашивает по именам на всякий случай.
	MeshLibrary.ApplyIslandLook(model, false)
	model.Parent = folder
	print(string.format("[PlotManager] Остров собран из %d деталей", count))
	return model
end

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

	-- 1) детали (island_grass, island_road, ...) → 2) цельный main_island → 3) фолбэк
	local islandMesh = tryBuildIslandPieces(folder, position) or tryBuildIslandMesh(folder, position)
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

-- Деревянного трапа с воды БОЛЬШЕ НЕТ: остров опущен (Config.PLOT_POSITIONS,
-- Y=12) так, что песчаная лего-лесенка каймы встречает воду — из океана на
-- пляж теперь просто выходишь по ступеням в любом месте берега.

-- Кнопки-«блины» (слоты, стенды ракет, ПВО) раньше ВИСЕЛИ над поверхностью:
-- их Y считался от уровня газона, а песчаная кайма ниже, платформа ракет выше.
-- Ставим блин на ФАКТИЧЕСКУЮ поверхность: луч вниз, низ блина на землю.
function PlotManager.SnapPadToSurface(pad)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { pad }
	params.IgnoreWater = true
	local from = pad.Position + Vector3.new(0, 30, 0)
	local hit = workspace:Raycast(from, Vector3.new(0, -90, 0), params)
	if hit then
		-- Блин — цилиндр, лежащий на боку: толщина = Size.X.
		pad.Position = Vector3.new(pad.Position.X, hit.Position.Y + pad.Size.X / 2 + 0.05, pad.Position.Z)
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
	-- Roblox центрирует MeshPart по bbox КРОНЫ, а ствол смещён от её центра:
	-- компенсируем spot.trunkOff, чтобы именно СТВОЛ встал в точку spot.offset
	-- (иначе пальма кроной стоит где надо, а стволом вылезает на дорогу).
	local yawCF = CFrame.Angles(0, math.rad(yawDeg), 0)
	local trunkShift = yawCF:VectorToWorldSpace((spot.trunkOff or Vector3.zero) * scale)
	meshPart.CFrame = CFrame.new(basePos - trunkShift + Vector3.new(0, meshPart.Size.Y / 2, 0)) * yawCF
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

	-- Спавн НЕВИДИМ: раньше это был "второй квадрат песка", плававший над пляжем
	-- рядом с ракетой. Точка респавна работает, но геометрии больше не видно.
	-- Точка (0, 16): северный центр газона — пиццерия и кафе теперь прижаты к
	-- южному краю и смотрят фасадами на север, игрок спавнится ЛИЦОМ к ним и
	-- их кнопкам (старая точка (0, 40) оказалась бы внутри кафе).
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "PlotSpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = position + Vector3.new(0, SURFACE_OFFSET + 1.05, 16)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = false
	spawn.Duration = 0
	spawn.Parent = folder

	-- Launcher models are added here as the player expands from one to four.
	local siloFolder = Instance.new("Folder")
	siloFolder.Name = "RocketSilo"
	siloFolder.Parent = folder

	-- Кнопки покупки зданий — плоские зелёные "блины". Слоты 3-5 — у кромки
	-- песка (мост ведёт на под-остров), слоты 1-2 (пиццерия и кафе) — ПРЯМО НА
	-- ГАЗОНЕ главного острова (Config.LAWN_SLOTS). Покупка/прокачка срабатывает
	-- по НАСТУПАНИЮ (Touched). Над каждой висит ценник (BillboardGui).
	local slotsData = {}
	local edgeR = Config.PLOT_CENTER_SIZE * 0.64 - 8
	for slotIdx, offset in ipairs(Config.SLOT_OFFSETS) do
		local lawn = Config.LAWN_SLOTS[slotIdx]
		local slotCenter, edgePos, padPos
		if lawn then
			-- Пиццерия/кафе на газоне: кнопка стоит между зданием и спавном.
			slotCenter = position + lawn.offset
			edgePos = slotCenter
			padPos = position + lawn.padOffset + Vector3.new(0, SURFACE_OFFSET + 0.6, 0)
		else
			local dir = offset.Unit
			edgePos = position + dir * edgeR
			slotCenter = position + offset
			-- Сдвигаем кнопку ВБОК от радиальной линии (по ней идёт мост/тропа):
			-- кнопка не пересекает мост.
			local side = dir:Cross(Vector3.new(0, 1, 0))
			padPos = edgePos + side * 9 + Vector3.new(0, SURFACE_OFFSET + 0.8, 0)
		end

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
		-- Кнопка прижимается к фактической поверхности (раньше висела над песком).
		PlotManager.SnapPadToSurface(buyPad)

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
			center = slotCenter,
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
		-- Круг ложится на фактическую поверхность (серая платформа поднята).
		PlotManager.SnapPadToSurface(pad)

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

	-- Стенд: ЛЕГО-МЕШ ракеты (rocket_mkN из Blender, чем выше Mark — тем крупнее),
	-- та же высота, что у процедурной, чтобы точка старта не поехала.
	-- Фолбэк — общий конструктор RocketFactory (как у летящей ракеты).
	local meshRocket = MeshLibrary.FindPart(Config.ROCKETS.FOLDER, { "Mk" .. mark, "rocket_mk" .. mark })

	-- Roblox центрирует меш по bbox, а ось mk1/mk2 смещена от центра bbox
	-- (несимметричные плавники): ракета стояла НЕ по центру круга. Двигаем
	-- КРУГ (площадку и обод) под фактическую ось ракеты, сама ракета не едет.
	local axisShift = Vector3.zero
	if meshRocket then
		local preScale = RocketFactory.GetHeight(mark, 1) / math.max(meshRocket.Size.Y, 0.001)
		local off = Config.ROCKETS.AXIS_OFF[mark] or Vector3.zero
		axisShift = Vector3.new(off.X, 0, off.Z) * preScale
	end
	local axisPos = basePos + axisShift

	-- Бетонная площадка и обод — под осью ракеты; нижняя грань не копланарна поверхности.
	local pad = makeCylinder(model, "Pad", 0.4, 13, axisPos + Vector3.new(0, 0.45, 0), Color3.fromRGB(148, 150, 156), Enum.Material.Concrete)
	local rim = makeCylinder(model, "ReadyRim", 0.5, 14.4, axisPos + Vector3.new(0, 0.66, 0), teamColor, Enum.Material.Neon)
	rim.CanCollide = false

	local parts, window, height
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
		parts, window, height = RocketFactory.Build(model, CFrame.new(axisPos + Vector3.new(0, 0.65, 0)), teamColor, mark, 1, true)
	end
	-- Точка старта — на фактической оси ракеты.
	local origin = Vector3.new(axisPos.X, basePos.Y + 0.65 + height + 2, axisPos.Z)

	-- Красный таймер перезарядки НА МЕСТЕ ракеты: виден ТОЛЬКО пока стенд в
	-- кулдауне (ракета в это время невидима), см. PlotManager.ShowReloadTimer.
	local reloadGui = Instance.new("BillboardGui")
	reloadGui.Name = "ReloadTimer"
	reloadGui.Size = UDim2.new(0, 96, 0, 42)
	reloadGui.StudsOffset = Vector3.new(0, math.max(6, height * 0.55), 0)
	reloadGui.AlwaysOnTop = true
	reloadGui.MaxDistance = 260
	reloadGui.Enabled = false
	reloadGui.Parent = pad
	local reloadLabel = Instance.new("TextLabel")
	reloadLabel.Name = "ReloadLabel"
	reloadLabel.Size = UDim2.new(1, 0, 1, 0)
	reloadLabel.BackgroundTransparency = 1
	reloadLabel.Font = Enum.Font.GothamBlack
	reloadLabel.TextSize = 30
	reloadLabel.TextColor3 = Color3.fromRGB(255, 64, 56)
	reloadLabel.TextStrokeColor3 = Color3.fromRGB(35, 0, 0)
	reloadLabel.TextStrokeTransparency = 0.3
	reloadLabel.Text = ""
	reloadLabel.Parent = reloadGui

	-- Запуск идёт через прицел (клавиша E на стенде), см. HudManager.

	model.PrimaryPart = pad
	plot.launchers[launcherIndex] = {
		model = model,
		parts = parts,
		window = window,
		rim = rim,
		origin = origin,
		mark = mark,
		reloadGui = reloadGui,
		reloadLabel = reloadLabel,
		reloadToken = 0,
	}
	return plot.launchers[launcherIndex]
end

-- Красный отсчёт на месте ракеты, пока стенд перезаряжается (1 раз в 0.2с).
-- token отменяет старый отсчёт, если стенд перестроили/перезапустили таймер.
function PlotManager.ShowReloadTimer(player, launcherIndex, seconds)
	local _, plot = PlotManager.GetPlotByPlayer(player)
	local launcher = plot and plot.launchers[launcherIndex]
	if not launcher or not launcher.reloadGui then return end
	launcher.reloadToken = (launcher.reloadToken or 0) + 1
	local token = launcher.reloadToken
	local endsAt = os.clock() + seconds
	launcher.reloadGui.Enabled = true
	task.spawn(function()
		while os.clock() < endsAt do
			if launcher.reloadToken ~= token or not launcher.model.Parent then return end
			launcher.reloadLabel.Text = tostring(math.max(1, math.ceil(endsAt - os.clock())))
			task.wait(0.2)
		end
		if launcher.reloadToken == token and launcher.model.Parent then
			launcher.reloadGui.Enabled = false
		end
	end)
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
