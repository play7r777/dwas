-- RocketManager.luau - launcher purchases, upgrades, reloads, and authoritative combat
--
-- v3: покупка и прокачка стендов идёт наступанием на зелёный круг перед стендом
-- (rocketPads из PlotManager). Урон ракеты растёт с уровнем стенда, а каждые
-- 5 уровней стенд перестраивается в новое поколение (Mark I..IV).
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Config            = require(sharedFolder:WaitForChild("Config"))
local Remotes           = require(sharedFolder:WaitForChild("Remotes"))
local DataManager       = require(script.Parent:WaitForChild("DataManager"))
local PlotManager       = require(script.Parent:WaitForChild("PlotManager"))
local FarmManager       = require(script.Parent:WaitForChild("FarmManager"))
local RocketFactory     = require(script.Parent:WaitForChild("RocketFactory"))

local RocketManager = {}

local launcherReady = {}
local lastRequest = {}

-- Анти-двойное срабатывание зелёных кругов: после покупки/прокачки игрок обязан
-- СОЙТИ с круга, прежде чем тот сработает снова (фикс «стоит 410, списалось ~700»).
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

local function notify(player, message, kind)
	Remotes.Get("Notify"):FireClient(player, message, kind or "info")
end

-- Близость к установке больше НЕ требуется: ракету можно отправить и с кнопки
-- Attack (удалённо). Если клиент передал номер стенда (стоял у него по E или
-- выбрал в меню) — летит ИМЕННО этот стенд, а не первый готовый.

-- Летящая ракета строится СЕРВЕРОМ (реплицируется всем) из ТОГО ЖЕ конструктора,
-- что и стенд на базе (RocketFactory): то же поколение Mark, тот же цвет команды,
-- те же детали — в полёте ракета выглядит точно как на базе (масштаб 0.5, нос по -Z).
local FLY_SCALE = 0.5

local function buildFlyingRocket(originPos, mark, teamColor)
	local model = Instance.new("Model")
	model.Name = "FlyingRocket"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.4, 0.4, 0.4)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CFrame = CFrame.new(originPos)
	root.Parent = model
	model.PrimaryPart = root

	-- Ось ракеты (+Y конструктора) разворачиваем в -Z корня (нос вперёд),
	-- центр корпуса совмещаем с корнем.
	local height = RocketFactory.GetHeight(mark, FLY_SCALE)
	local baseCF = root.CFrame * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, -height / 2, 0)
	RocketFactory.Build(model, baseCF, teamColor, mark, FLY_SCALE, false)

	local front = Instance.new("Attachment")
	front.Position = Vector3.new(0, 0, -height * 0.55)
	front.Parent = root
	local back = Instance.new("Attachment")
	back.Position = Vector3.new(0, 0, height * 0.5)
	back.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = front
	trail.Attachment1 = back
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 205, 70), teamColor)
	trail.Lifetime = 0.35
	trail.MinLength = 0.4
	trail.Parent = root

	local light = Instance.new("PointLight")
	light.Brightness = 8
	light.Range = 20
	light.Color = Color3.fromRGB(255, 150, 50)
	light.Parent = root

	-- Звук полёта: свист двигателя (луп, встроенный ассет Roblox — всегда доступен)
	-- и «выстрел» на старте. Громкость лупа плавно гасится перед прилётом.
	local whoosh = Instance.new("Sound")
	whoosh.Name = "FlightLoop"
	whoosh.SoundId = "rbxasset://sounds/Rocket whoosh 01.wav"
	whoosh.Looped = true
	whoosh.Volume = 0
	whoosh.RollOffMinDistance = 15
	whoosh.RollOffMaxDistance = 350
	whoosh.Parent = root
	whoosh:Play()

	local shot = Instance.new("Sound")
	shot.Name = "LaunchShot"
	shot.SoundId = "rbxasset://sounds/Rocket shot.wav"
	shot.Volume = 0.65
	shot.RollOffMaxDistance = 300
	shot.Parent = root
	shot:Play()

	return model
end

local function arcPos(origin, target, t)
	local straight = origin:Lerp(target, t)
	local height = math.sin(t * math.pi) * Config.ROCKET_ARC
	return Vector3.new(straight.X, straight.Y + height, straight.Z)
end

-- Спавнит ракету, ведёт её по баллистической дуге на сервере, просит клиента
-- стрелка вести камеру за этим инстансом, затем вызывает onImpact в точке удара.
local function flyRocket(shooter, originPos, targetPos, mark, teamColor, onImpact)
	local model = buildFlyingRocket(originPos, mark, teamColor)
	model.Parent = workspace

	-- Клиенту-стрелку сообщаем, какую ракету вести камерой.
	if shooter and shooter.Parent then
		Remotes.Get("RocketFollow"):FireClient(shooter, model, targetPos)
	end

	task.spawn(function()
		local root = model.PrimaryPart
		local whoosh = root and root:FindFirstChild("FlightLoop")
		local dist = (targetPos - originPos).Magnitude
		local duration = math.clamp(dist / Config.ROCKET_SPEED, 0.9, Config.ROCKET_ANIM_TIME)
		local elapsed = 0
		while elapsed < duration and model.Parent do
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt
			local t = math.clamp(elapsed / duration, 0, 1)
			local pos = arcPos(originPos, targetPos, t)
			local nextPos = arcPos(originPos, targetPos, math.min(t + 0.04, 1))
			local dir = nextPos - pos
			if dir.Magnitude > 0.001 then
				model:PivotTo(CFrame.lookAt(pos, pos + dir))
			else
				model:PivotTo(CFrame.new(pos))
			end
			-- Плавная огибающая свиста: быстрый вход в начале, затухание к прилёту.
			if whoosh then
				if t < 0.12 then
					whoosh.Volume = 0.55 * (t / 0.12)
				elseif t > 0.85 then
					whoosh.Volume = 0.55 * math.max(0, 1 - (t - 0.85) / 0.15)
				else
					whoosh.Volume = 0.55
				end
			end
		end
		model:Destroy()
		if onImpact then onImpact() end
	end)
end

local function sendRocketState(player)
	local count = DataManager.GetLauncherCount(player)
	local readyCount = 0
	local reloads = {}
	local now = workspace:GetServerTimeNow()
	for index = 1, count do
		local readyAt = launcherReady[player] and launcherReady[player][index] or 0
		if readyAt <= now then readyCount += 1 else reloads[index] = math.max(0, readyAt - now) end
	end
	Remotes.Get("RocketStateChanged"):FireClient(player, {
		launchers = count,
		ready = readyCount,
		reloads = reloads,
	})
end

-- Актуализирует зелёные круги стендов: прокачка / покупка следующего / скрыто.
local function refreshPads(player)
	local plotId = select(1, PlotManager.GetPlotByPlayer(player))
	if not plotId then return end
	local count = DataManager.GetLauncherCount(player)
	for index = 1, Config.MAX_LAUNCHERS do
		if index <= count then
			local level = DataManager.GetLauncherLevel(player, index)
			if level >= Config.MAX_ROCKET_LEVEL then
				PlotManager.SetRocketPadState(plotId, index, "max", string.format("Ракета ур.%d\nМАКС. УРОВЕНЬ", level))
			else
				PlotManager.SetRocketPadState(plotId, index, "upgrade", string.format("Прокачка ур.%d → %d\n$%d", level, level + 1, Config.RocketUpgradeCost(level + 1)))
			end
		elseif index == count + 1 then
			PlotManager.SetRocketPadState(plotId, index, "buy", string.format("Купить ракету %d\n$%d", index, Config.LAUNCHER_COSTS[index]))
		else
			PlotManager.SetRocketPadState(plotId, index, "locked")
		end
	end
end

local function createOwnedLaunchers(player)
	launcherReady[player] = launcherReady[player] or {}
	for index = 1, DataManager.GetLauncherCount(player) do
		PlotManager.CreateLauncher(player, index, DataManager.GetLauncherLevel(player, index))
		launcherReady[player][index] = launcherReady[player][index] or 0
	end
	refreshPads(player)
	sendRocketState(player)
end

-- Наступание владельца на зелёный круг: покупка следующего стенда или прокачка купленного.
local function onPadStep(player, index)
	local count = DataManager.GetLauncherCount(player)

	if index <= count then
		-- ПРОКАЧКА
		local level = DataManager.GetLauncherLevel(player, index)
		if level >= Config.MAX_ROCKET_LEVEL then return end
		local oldMark = Config.RocketMark(level)
		local ok, result = DataManager.UpgradeLauncher(player, index)
		if not ok then
			notify(player, result, "error")
			return
		end
		local newMark = Config.RocketMark(result)
		if newMark ~= oldMark then
			-- Эволюция внешнего вида каждые 5 уровней.
			PlotManager.RebuildLauncher(player, index, result)
			local now = workspace:GetServerTimeNow()
			local readyAt = launcherReady[player] and launcherReady[player][index] or 0
			PlotManager.SetLauncherReady(player, index, readyAt <= now)
			notify(player, string.format("Ракета %d эволюционировала — Mk %d!", index, newMark), "success")
		else
			notify(player, string.format("Ракета %d прокачана до ур.%d", index, result), "success")
		end
		refreshPads(player)
	elseif index == count + 1 then
		-- ПОКУПКА следующего стенда
		local ok, result = DataManager.BuyNextLauncher(player)
		if not ok then
			notify(player, result, "error")
			return
		end
		launcherReady[player] = launcherReady[player] or {}
		launcherReady[player][result] = 0
		PlotManager.CreateLauncher(player, result, 1)
		sendRocketState(player)
		refreshPads(player)
		notify(player, string.format("Установка %d построена", result), "success")
	end
end

-- Пытается «застолбить» конкретный стенд: ставит его на перезарядку и возвращает true.
local function tryTakeLauncher(player, index)
	local now = workspace:GetServerTimeNow()
	launcherReady[player] = launcherReady[player] or {}
	if (launcherReady[player][index] or 0) <= now then
		launcherReady[player][index] = now + Config.ROCKET_RELOAD
		PlotManager.SetLauncherReady(player, index, false)
		sendRocketState(player)
		task.delay(Config.ROCKET_RELOAD, function()
			if player.Parent and launcherReady[player] and launcherReady[player][index] then
				launcherReady[player][index] = 0
				PlotManager.SetLauncherReady(player, index, true)
				sendRocketState(player)
			end
		end)
		return true
	end
	return false
end

-- preferredIndex: стенд, у которого игрок стоял (E) или который выбрал в меню
-- Attack — стреляет ИМЕННО он. Без preferredIndex берём первый готовый.
local function takeReadyLauncher(player, preferredIndex)
	local count = DataManager.GetLauncherCount(player)
	if preferredIndex then
		if preferredIndex >= 1 and preferredIndex <= count and tryTakeLauncher(player, preferredIndex) then
			return preferredIndex
		end
		return nil
	end
	for index = 1, count do
		if tryTakeLauncher(player, index) then
			return index
		end
	end
	return nil
end

function RocketManager.Init()
	local launchEvent = Remotes.Get("LaunchRocket")

	local function setupPlayer(player)
		task.spawn(function()
			for _ = 1, 30 do
				if not player.Parent then return end
				local plotId = select(1, PlotManager.GetPlotByPlayer(player))
				if plotId and DataManager.GetData(player) then
					createOwnedLaunchers(player)
					return
				end
				task.wait(0.2)
			end
		end)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(function(player)
		launcherReady[player] = nil
		lastRequest[player] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do setupPlayer(player) end

	-- Наступание на зелёные круги стендов: ровно ОДИН раз за визит (надо сойти
	-- с круга, чтобы он сработал снова) — никаких двойных списаний.
	for plotId, plot in pairs(PlotManager.GetAllPlots()) do
		for index, rp in pairs(plot.rocketPads or {}) do
			rp.pad.Touched:Connect(function(hit)
				local player = Players:GetPlayerFromCharacter(hit.Parent)
				if not player or plot.owner ~= player then return end
				local key = string.format("%d:%d:%d", player.UserId, plotId, index)
				if padLock[key] then return end
				padLock[key] = { player = player, pos = rp.pad.Position, radius = 8 }
				onPadStep(player, index)
			end)
		end
	end

	-- Совместимость: старый ремоут покупки установки (основной путь — зелёные круги).
	Remotes.Get("BuyLauncher").OnServerEvent:Connect(function(player)
		local success, result = DataManager.BuyNextLauncher(player)
		if not success then notify(player, result, "error") return end
		launcherReady[player] = launcherReady[player] or {}
		launcherReady[player][result] = 0
		PlotManager.CreateLauncher(player, result, 1)
		sendRocketState(player)
		refreshPads(player)
		notify(player, string.format("Установка %d построена", result), "success")
	end)

	-- Клиент шлёт целевой остров, точку прицела (raycast по 3D-миру) и, опционально,
	-- номер стенда (стоял у него по E / выбрал в меню Attack).
	launchEvent.OnServerEvent:Connect(function(player, targetPlotId, targetPos, launcherIndexArg)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.2 then return end
		lastRequest[player] = now
		if type(targetPlotId) ~= "number" or targetPlotId % 1 ~= 0 then return end

		local targetPlot = PlotManager.GetPlot(targetPlotId)
		local myPlotId = select(1, PlotManager.GetPlotByPlayer(player))
		-- Можно бить по ЛЮБОМУ острову (в т.ч. пустому без владельца), кроме своего.
		if not targetPlot or myPlotId == targetPlotId then
			notify(player, "Недопустимая цель", "error")
			return
		end

		local preferredIndex = nil
		if type(launcherIndexArg) == "number" and launcherIndexArg % 1 == 0 then
			preferredIndex = launcherIndexArg
		end

		local launcherIndex = takeReadyLauncher(player, preferredIndex)
		if not launcherIndex then
			notify(player, preferredIndex and "Эта ракета перезаряжается" or "Все ракеты перезаряжаются", "error")
			return
		end
		local originPos = PlotManager.GetLauncherOrigin(player, launcherIndex)
		if not originPos then return end

		-- Урон и внешний вид летящей ракеты зависят от уровня выбранного стенда.
		local level = DataManager.GetLauncherLevel(player, launcherIndex)
		local damage = Config.RocketDamageForLevel(level)
		local mark = Config.RocketMark(level)
		local _, myPlot = PlotManager.GetPlotByPlayer(player)
		local teamColor = myPlot and myPlot.themeColor or Color3.fromRGB(220, 70, 60)

		-- Точка удара: либо переданная клиентом точка (ограниченная областью острова,
		-- чтобы нельзя было целиться мимо карты), либо центр острова со случайным разбросом.
		local impactPos
		if typeof(targetPos) == "Vector3" then
			local flat = Vector3.new(targetPos.X, targetPlot.center.Y, targetPos.Z)
			local off = flat - targetPlot.center
			local maxR = Config.PLOT_CENTER_SIZE
			if off.Magnitude > maxR then off = off.Unit * maxR end
			impactPos = targetPlot.center + off + Vector3.new(0, 10, 0)
		else
			impactPos = targetPlot.center + Vector3.new((math.random() - 0.5) * 30, 10, (math.random() - 0.5) * 30)
		end

		flyRocket(player, originPos, impactPos, mark, teamColor, function()
			-- Авторитетный прилёт: урон/оглушение зданий считает сервер.
			local destroyed = FarmManager.ApplyRocketImpact(targetPlotId, impactPos, damage)
			Remotes.Get("RocketImpact"):FireAllClients({
				pos = impactPos,
				destroyed = destroyed,
				shooterName = player.DisplayName,
				shooterUserId = player.UserId,
				targetPlotId = targetPlotId,
			})
		end)
	end)
end

return RocketManager
