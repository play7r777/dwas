-- AirDefenseManager.luau — ПВО-миниган: сбивает вражеские ракеты на подлёте.
--
-- Как это работает:
--  • Возле турели (на газоне) стоит зелёный круг: наступил — купил ПВО, наступил
--    ещё раз — прокачал (уровни 1..5, см. Config.AIR_DEFENSE).
--  • Чем выше уровень — тем ЧАЩЕ турель стреляет (FIRE_INTERVAL) и тем ВЫШЕ шанс
--    попадания за выстрел (HIT_CHANCE). Гарантий нет: может сбить, а может
--    промазать — каждый выстрел бросает кость.
--  • RocketManager ведёт реестр летящих ракет; турель цели выбирает ракеты,
--    летящие ИМЕННО на её остров, в радиусе RANGE. Попадание выставляет
--    rec.shotDown — ракета взрывается в воздухе, здания целы.
--  • Внешний вид: Blender-меши ReplicatedStorage/AirDefenseMeshes/{Base,Head,
--    Barrels} (assets/air_defense). Пока мешей нет — процедурная турель из
--    партов той же формы. Башня доворачивается на ракету, блок стволов крутится.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Debris            = game:GetService("Debris")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Config        = require(sharedFolder:WaitForChild("Config"))
local Remotes       = require(sharedFolder:WaitForChild("Remotes"))
local DataManager   = require(script.Parent:WaitForChild("DataManager"))
local PlotManager   = require(script.Parent:WaitForChild("PlotManager"))
local RocketManager = require(script.Parent:WaitForChild("RocketManager"))
local MeshLibrary   = require(script.Parent:WaitForChild("MeshLibrary"))

local AirDefenseManager = {}

local AD = Config.AIR_DEFENSE
local SURFACE_OFFSET = 10 -- высота песка над Y центра плота (как в PlotManager)

local units = {} -- [plotId] = { player, level, folder, pivotPos, headParts, barrelParts, ... }
local pads = {}  -- [plotId] = { pad, billboard, label }

-- Анти-двойное срабатывание круга (та же схема, что у стендов ракет).
local padLock = {}
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

local function notify(player, message, kind)
	Remotes.Get("Notify"):FireClient(player, message, kind or "info")
end

local function makePart(parent, name, size, cframe, color, material, canCollide)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = canCollide == true
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- ============================================================
-- Сборка турели
-- ============================================================

-- Турель из Blender-мешей: три части (Base/Head/Barrels) с пивотами из Config.
-- Понимает и «Base/Head/Barrels», и имена файлов после Import 3D
-- («air_defense_base/head/barrels») — переименовывать не нужно.
local function tryBuildMeshTurret(model, basePos, restAim)
	local baseT = MeshLibrary.FindPart(AD.FOLDER, { "Base", "air_defense_base" })
	local headT = MeshLibrary.FindPart(AD.FOLDER, { "Head", "air_defense_head" })
	local barrT = MeshLibrary.FindPart(AD.FOLDER, { "Barrels", "air_defense_barrels" })
	if not (baseT and headT and barrT) then return nil end

	local M = AD.MESH
	local s = AD.HEIGHT / M.TOTAL_H -- стадов на юнит меша
	-- Меши смотрят по +Z детали, а бою нужен -Z (LookVector): доворот на 180°.
	local FLIP = CFrame.Angles(0, math.pi, 0)

	local base = baseT -- FindPart уже вернул клон
	base.Anchored = true
	base.CanCollide = true
	base.Size = base.Size * s
	local baseA = CFrame.lookAt(basePos, basePos + restAim) * FLIP
	base.CFrame = baseA * CFrame.new(M.BASE_BB * s)
	base.Parent = model

	local pivotPos = basePos + Vector3.new(0, M.HEAD_PIVOT_Z * s, 0)
	local A0 = CFrame.lookAt(pivotPos, pivotPos + restAim)

	local head = headT -- клон из FindPart
	head.Anchored = true
	head.CanCollide = false
	head.Size = head.Size * s
	head.CFrame = A0 * FLIP * CFrame.new(M.HEAD_BB * s)
	head.Parent = model

	local barrels = barrT -- клон из FindPart
	barrels.Anchored = true
	barrels.CanCollide = false
	barrels.Size = barrels.Size * s
	local barrelPivotOff = FLIP * CFrame.new(M.BARREL_PIVOT * s)
	local bp0 = A0 * barrelPivotOff
	barrels.CFrame = bp0 * CFrame.new(M.BARR_BB * s)
	barrels.Parent = model

	return {
		pivotPos = pivotPos,
		headParts = { { part = head, off = A0:Inverse() * head.CFrame } },
		barrelPivotOff = barrelPivotOff,
		barrelParts = { { part = barrels, off = bp0:Inverse() * barrels.CFrame } },
		muzzleOff = M.MUZZLE * s,
		primary = base,
	}
end

-- Процедурный фолбэк: та же турель из обычных партов (пропорции Blender-модели).
local function buildProceduralTurret(model, basePos, restAim)
	local sp = AD.HEIGHT / 11.6
	local GRAPHITE = Color3.fromRGB(30, 32, 35)
	local STEEL = Color3.fromRGB(122, 127, 132)
	local STEEL_D = Color3.fromRGB(78, 83, 88)
	local OLIVE = Color3.fromRGB(96, 101, 56)
	local OLIVE_D = Color3.fromRGB(70, 75, 40)
	local YELLOW = Color3.fromRGB(240, 198, 25)

	-- Основание (статичное): барабан + пьедестал + жёлтая окантовка.
	local function up(h) return basePos + Vector3.new(0, h * sp, 0) end
	local drum = makePart(model, "Drum", Vector3.new(2.4, 8.6, 8.6) * sp,
		CFrame.new(up(1.2)) * CFrame.Angles(0, 0, math.rad(90)), GRAPHITE, Enum.Material.Metal, true)
	drum.Shape = Enum.PartType.Cylinder
	makePart(model, "Pedestal", Vector3.new(6.2, 3.6, 6.2) * sp, CFrame.new(up(4.5)), STEEL, Enum.Material.DiamondPlate, true)
	makePart(model, "TrimF", Vector3.new(6.5, 0.4, 0.5) * sp, CFrame.new(up(6.1) + restAim * (3.0 * sp)), YELLOW, Enum.Material.SmoothPlastic)
	makePart(model, "TrimB", Vector3.new(6.5, 0.4, 0.5) * sp, CFrame.new(up(6.1) - restAim * (3.0 * sp)), YELLOW, Enum.Material.SmoothPlastic)
	local ring = makePart(model, "Ring", Vector3.new(0.7, 5.6, 5.6) * sp,
		CFrame.new(up(6.45)) * CFrame.Angles(0, 0, math.rad(90)), GRAPHITE, Enum.Material.Metal)
	ring.Shape = Enum.PartType.Cylinder

	local pivotPos = basePos + Vector3.new(0, 8.1 * sp, 0)
	local A0 = CFrame.lookAt(pivotPos, pivotPos + restAim)
	local headParts = {}

	local function headPart(name, size, offCF, color, material, shape)
		local part = makePart(model, name, size, A0 * offCF, color, material)
		if shape then part.Shape = shape end
		table.insert(headParts, { part = part, off = offCF })
		return part
	end

	-- Башня: бронекороб + панели + жёлтые акценты + ящик боекомплекта (в
	-- aim-пространстве -Z = направление стрельбы).
	headPart("Head", Vector3.new(6.4, 3.2, 7.0) * sp, CFrame.new(0, 0, 0.4 * sp), OLIVE, Enum.Material.SmoothPlastic)
	headPart("PanelL", Vector3.new(0.2, 2.0, 4.4) * sp, CFrame.new(-3.28 * sp, 0, 0.5 * sp), OLIVE_D, Enum.Material.SmoothPlastic)
	headPart("PanelR", Vector3.new(0.2, 2.0, 4.4) * sp, CFrame.new(3.28 * sp, 0, 0.5 * sp), OLIVE_D, Enum.Material.SmoothPlastic)
	headPart("TrimHL", Vector3.new(1.6, 0.4, 0.5) * sp, CFrame.new(-2.3 * sp, 1.5 * sp, -3.1 * sp), YELLOW, Enum.Material.SmoothPlastic)
	headPart("TrimHR", Vector3.new(1.6, 0.4, 0.5) * sp, CFrame.new(2.3 * sp, 1.5 * sp, -3.1 * sp), YELLOW, Enum.Material.SmoothPlastic)
	headPart("Ammo", Vector3.new(1.7, 2.3, 3.6) * sp, CFrame.new(3.9 * sp, -0.2 * sp, -0.6 * sp), OLIVE_D, Enum.Material.SmoothPlastic)
	headPart("Mount", Vector3.new(2.6, 2.2, 1.6) * sp, CFrame.new(0, 0, -3.9 * sp), STEEL_D, Enum.Material.Metal)

	-- Блок стволов: пивот на 4.6 юнита вперёд от пивота башни.
	local barrelPivotOff = CFrame.new(0, 0, -4.6 * sp)
	local bp0 = A0 * barrelPivotOff
	local barrelParts = {}
	local BARREL_LEN = 6.6 * sp

	local function barrelPart(name, size, offCF, color, material, shape)
		local part = makePart(model, name, size, bp0 * offCF, color, material)
		if shape then part.Shape = shape end
		table.insert(barrelParts, { part = part, off = offCF })
		return part
	end

	-- Цилиндр Roblox лежит вдоль X: доворот Angles(0, 90°, 0) кладёт его вдоль Z.
	local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)
	barrelPart("Hub", Vector3.new(1.4 * sp, 2.5 * sp, 2.5 * sp), CFrame.new(0, 0, 0.5 * sp) * ALONG_Z, GRAPHITE, Enum.Material.Metal, Enum.PartType.Cylinder)
	barrelPart("Shaft", Vector3.new(BARREL_LEN - sp, 0.9 * sp, 0.9 * sp), CFrame.new(0, 0, -(1.2 * sp + (BARREL_LEN - sp) / 2)) * ALONG_Z, STEEL_D, Enum.Material.Metal, Enum.PartType.Cylinder)
	for i = 1, 6 do
		local a = math.rad(60 * i)
		local ox = math.cos(a) * 0.78 * sp
		local oy = math.sin(a) * 0.78 * sp
		barrelPart("Tube_" .. i, Vector3.new(BARREL_LEN, 0.54 * sp, 0.54 * sp),
			CFrame.new(ox, oy, -(1.2 * sp + BARREL_LEN / 2)) * ALONG_Z, STEEL, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	barrelPart("Muzzle", Vector3.new(1.0 * sp, 2.16 * sp, 2.16 * sp), CFrame.new(0, 0, -(1.2 * sp + BARREL_LEN - 0.3 * sp)) * ALONG_Z, GRAPHITE, Enum.Material.Metal, Enum.PartType.Cylinder)

	return {
		pivotPos = pivotPos,
		headParts = headParts,
		barrelPivotOff = barrelPivotOff,
		barrelParts = barrelParts,
		muzzleOff = Vector3.new(0, 0, -7.8 * sp),
		primary = drum,
	}
end

local function buildTurret(plotId, player, level)
	local plot = PlotManager.GetPlot(plotId)
	if not plot then return nil end
	local old = plot.folder:FindFirstChild("AirDefense")
	if old then old:Destroy() end

	local model = Instance.new("Model")
	model.Name = "AirDefense"
	model:SetAttribute("Level", level)
	model.Parent = plot.folder

	local basePos = plot.center + AD.OFFSET + Vector3.new(0, SURFACE_OFFSET, 0)
	-- В покое смотрим от центра острова наружу (в сторону моря).
	local flat = Vector3.new(AD.OFFSET.X, 0, AD.OFFSET.Z)
	local restAim = flat.Magnitude > 0.001 and flat.Unit or Vector3.new(0, 0, 1)

	local rig = tryBuildMeshTurret(model, basePos, restAim) or buildProceduralTurret(model, basePos, restAim)
	model.PrimaryPart = rig.primary

	-- Звук очереди (переиспользуем один Sound на турель).
	local sound = Instance.new("Sound")
	sound.Name = "FireSound"
	sound.SoundId = "rbxasset://sounds/Rocket shot.wav"
	sound.Volume = 0.35
	sound.PlaybackSpeed = 1.6
	sound.RollOffMaxDistance = 260
	sound.Parent = rig.primary

	units[plotId] = {
		plotId = plotId,
		player = player,
		level = level,
		folder = model,
		pivotPos = rig.pivotPos,
		headParts = rig.headParts,
		barrelParts = rig.barrelParts,
		barrelPivotOff = rig.barrelPivotOff,
		muzzleOff = rig.muzzleOff,
		restAim = restAim,
		aimDir = restAim,
		spin = 0,
		spinSpeed = 0,
		nextShotAt = 0,
		sound = sound,
	}
	return units[plotId]
end

-- ============================================================
-- Зелёный круг покупки/прокачки
-- ============================================================

local function refreshPad(plotId)
	local rec = pads[plotId]
	if not rec then return end
	local plot = PlotManager.GetPlot(plotId)
	local owner = plot and plot.owner
	if not owner then
		rec.pad.Transparency = 1
		rec.pad.CanCollide = false
		rec.billboard:SetAttribute("Unlocked", false)
		return
	end

	local level = DataManager.GetAirDefenseLevel(owner)
	rec.billboard:SetAttribute("Unlocked", true)
	if level == 0 then
		rec.pad.Transparency = 0
		rec.pad.CanCollide = true
		rec.label.Text = string.format("Построить ПВО\n$%d", AD.COST)
		rec.label.TextColor3 = Color3.fromRGB(240, 244, 246)
	elseif level < AD.MAX_LEVEL then
		rec.pad.Transparency = 0
		rec.pad.CanCollide = true
		rec.label.Text = string.format("ПВО ур.%d → %d\n$%d", level, level + 1, Config.AirDefenseUpgradeCost(level + 1))
		rec.label.TextColor3 = Color3.fromRGB(240, 244, 246)
	else
		rec.pad.Transparency = 0.35
		rec.pad.CanCollide = false
		rec.label.Text = string.format("ПВО ур.%d\nМАКС. УРОВЕНЬ", level)
		rec.label.TextColor3 = Color3.fromRGB(255, 224, 150)
	end
end

local function onPadStep(player, plotId)
	local level = DataManager.GetAirDefenseLevel(player)
	if level == 0 then
		local ok, result = DataManager.BuyAirDefense(player)
		if not ok then
			notify(player, result, "error")
			return
		end
		buildTurret(plotId, player, result)
		notify(player, "ПВО построено! Оно будет сбивать вражеские ракеты", "success")
	elseif level < AD.MAX_LEVEL then
		local ok, result = DataManager.UpgradeAirDefense(player)
		if not ok then
			notify(player, result, "error")
			return
		end
		local unit = units[plotId]
		if unit then
			unit.level = result
			if unit.folder then unit.folder:SetAttribute("Level", result) end
		else
			buildTurret(plotId, player, result)
		end
		notify(player, string.format("ПВО прокачано до ур.%d — стреляет быстрее и точнее", result), "success")
	end
	refreshPad(plotId)
end

local function buildPad(plotId)
	local plot = PlotManager.GetPlot(plotId)
	if not plot then return end

	local basePos = plot.center + AD.OFFSET + Vector3.new(0, SURFACE_OFFSET, 0)
	local toCenter = Vector3.new(-AD.OFFSET.X, 0, -AD.OFFSET.Z)
	toCenter = toCenter.Magnitude > 0.001 and toCenter.Unit or Vector3.new(0, 0, -1)
	local padPos = basePos + toCenter * 12 + Vector3.new(0, 0.55, 0)

	local pad = Instance.new("Part")
	pad.Name = "AirDefensePad"
	pad.Shape = Enum.PartType.Cylinder
	pad.Anchored = true
	pad.Size = Vector3.new(0.5, 10, 10)
	pad.Orientation = Vector3.new(0, 0, 90)
	pad.Position = padPos
	pad.Color = Color3.fromRGB(64, 224, 130)
	pad.Material = Enum.Material.Neon
	pad.Transparency = 1
	pad.CanCollide = false
	pad.Parent = plot.folder

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

	pads[plotId] = { pad = pad, billboard = billboard, label = label }

	pad.Touched:Connect(function(hit)
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		local plot2 = PlotManager.GetPlot(plotId)
		if not player or not plot2 or plot2.owner ~= player then return end
		local key = string.format("AD:%d:%d", player.UserId, plotId)
		if padLock[key] then return end
		padLock[key] = { player = player, pos = pad.Position, radius = 8 }
		onPadStep(player, plotId)
	end)
end

-- ============================================================
-- Стрельба
-- ============================================================

local function fire(unit, rocket)
	unit.nextShotAt = os.clock() + AD.FIRE_INTERVAL[math.clamp(unit.level, 1, #AD.FIRE_INTERVAL)]

	local aimCF = CFrame.lookAt(unit.pivotPos, rocket.pos)
	local barrelCF = aimCF * unit.barrelPivotOff * CFrame.Angles(0, 0, unit.spin)
	local muzzlePos = (barrelCF * CFrame.new(unit.muzzleOff)).Position

	-- Бросок кости: попали или промазали.
	local hit = math.random() < AD.HIT_CHANCE[math.clamp(unit.level, 1, #AD.HIT_CHANCE)]
	local targetPos
	if hit then
		targetPos = rocket.pos
	else
		targetPos = rocket.pos + Vector3.new(
			(math.random() - 0.5) * 22,
			(math.random() - 0.5) * 16,
			(math.random() - 0.5) * 22
		)
	end

	-- Трассер: тонкий неоновый луч от дула к точке (живёт мгновение).
	local dist = (targetPos - muzzlePos).Magnitude
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = Color3.fromRGB(255, 214, 70)
	tracer.Size = Vector3.new(0.3, 0.3, dist)
	tracer.CFrame = CFrame.lookAt(muzzlePos, targetPos) * CFrame.new(0, 0, -dist / 2)
	tracer.Parent = workspace
	Debris:AddItem(tracer, 0.07)

	-- Вспышка на дуле.
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 170, 40)
	flash.Size = Vector3.new(1.6, 1.6, 1.6)
	flash.Position = muzzlePos
	flash.Parent = workspace
	Debris:AddItem(flash, 0.06)

	if unit.sound then
		unit.sound.PlaybackSpeed = 1.45 + math.random() * 0.3
		unit.sound:Play()
	end

	if hit then
		rocket.shotDown = true
	else
		-- Промах: маленькая искра рядом с ракетой (визуально понятно, что мимо).
		local spark = Instance.new("Part")
		spark.Shape = Enum.PartType.Ball
		spark.Anchored = true
		spark.CanCollide = false
		spark.Material = Enum.Material.Neon
		spark.Color = Color3.fromRGB(255, 120, 60)
		spark.Size = Vector3.new(1.2, 1.2, 1.2)
		spark.Position = targetPos
		spark.Parent = workspace
		Debris:AddItem(spark, 0.12)
	end
end

-- Применяет текущий aim/spin к партам турели.
local function applyTransforms(unit)
	local aimCF = CFrame.lookAt(unit.pivotPos, unit.pivotPos + unit.aimDir)
	for _, rec in ipairs(unit.headParts) do
		rec.part.CFrame = aimCF * rec.off
	end
	local barrelCF = aimCF * unit.barrelPivotOff * CFrame.Angles(0, 0, unit.spin)
	for _, rec in ipairs(unit.barrelParts) do
		rec.part.CFrame = barrelCF * rec.off
	end
end

local function engagementLoop()
	RunService.Heartbeat:Connect(function(dt)
		local rockets = RocketManager.GetActiveRockets()
		local now = os.clock()
		for plotId, unit in pairs(units) do
			-- Ближайшая ракета, летящая на НАШ остров, в радиусе перехвата.
			local target, bestDist = nil, AD.RANGE
			for _, rec in pairs(rockets) do
				if rec.targetPlotId == plotId and not rec.shotDown then
					local d = (rec.pos - unit.pivotPos).Magnitude
					if d <= bestDist then
						target = rec
						bestDist = d
					end
				end
			end

			if target then
				-- Доворот на цель + раскрутка стволов.
				local dir = (target.pos - unit.pivotPos)
				if dir.Magnitude > 0.001 then
					unit.aimDir = unit.aimDir:Lerp(dir.Unit, math.clamp(dt * 10, 0, 1))
					-- Защита от вырожденного направления (лерп противоположных векторов)
					if unit.aimDir.Magnitude < 0.05 then
						unit.aimDir = dir.Unit
					else
						unit.aimDir = unit.aimDir.Unit
					end
				end
				unit.spinSpeed = math.min(unit.spinSpeed + dt * 40, 26)
				unit.spin = (unit.spin + unit.spinSpeed * dt) % (math.pi * 2)
				applyTransforms(unit)
				if now >= unit.nextShotAt then
					fire(unit, target)
				end
			elseif unit.spinSpeed > 0.05 or (unit.aimDir - unit.restAim).Magnitude > 0.02 then
				-- Целей нет: стволы плавно останавливаются, башня возвращается в покой.
				unit.spinSpeed = math.max(unit.spinSpeed - dt * 14, 0)
				unit.spin = (unit.spin + unit.spinSpeed * dt) % (math.pi * 2)
				unit.aimDir = unit.aimDir:Lerp(unit.restAim, math.clamp(dt * 2.5, 0, 1))
				applyTransforms(unit)
			end
		end
	end)
end

-- ============================================================
-- Init
-- ============================================================

function AirDefenseManager.Init()
	for plotId in pairs(PlotManager.GetAllPlots()) do
		buildPad(plotId)
	end

	local function setupPlayer(player)
		task.spawn(function()
			for _ = 1, 30 do
				if not player.Parent then return end
				local plotId = select(1, PlotManager.GetPlotByPlayer(player))
				if plotId and DataManager.GetData(player) then
					local level = DataManager.GetAirDefenseLevel(player)
					if level >= 1 then
						buildTurret(plotId, player, level)
					end
					refreshPad(plotId)
					return
				end
				task.wait(0.2)
			end
		end)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end

	Players.PlayerRemoving:Connect(function(player)
		for plotId, unit in pairs(units) do
			if unit.player == player then
				if unit.folder then unit.folder:Destroy() end
				units[plotId] = nil
				refreshPad(plotId)
			end
		end
	end)

	engagementLoop()
end

return AirDefenseManager
