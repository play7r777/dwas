-- RocketManager.luau - launcher purchases, reloads, and authoritative combat
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Config            = require(sharedFolder:WaitForChild("Config"))
local Remotes           = require(sharedFolder:WaitForChild("Remotes"))
local DataManager       = require(script.Parent:WaitForChild("DataManager"))
local PlotManager       = require(script.Parent:WaitForChild("PlotManager"))
local FarmManager       = require(script.Parent:WaitForChild("FarmManager"))

local RocketManager = {}

local launcherReady = {}
local lastRequest = {}

local function notify(player, message, kind)
	Remotes.Get("Notify"):FireClient(player, message, kind or "info")
end

-- Летящая ракета строится СЕРВЕРОМ (реплицируется всем): корень (нос по -Z),
-- корпус, конусный нос, полоса, стабилизаторы и дымный след. Урон/прилёт —
-- тоже на сервере, поэтому бой авторитетен.
local function buildFlyingRocket(originPos)
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

	local function piece(name, size, localCF, color, material, shape)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = root.CFrame * localCF
		part.Color = color
		part.Material = material
		part.Anchored = true
		part.CanCollide = false
		if shape then part.Shape = shape end
		part.Parent = model
		return part
	end

	piece("Body", Vector3.new(6, 1.8, 1.8), CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(232, 236, 238), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	piece("Stripe", Vector3.new(1.2, 1.85, 1.85), CFrame.new(0, 0, 0.6) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(220, 70, 60), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	for i = 1, 3 do
		local d = 1.8 * (1 - i * 0.28)
		piece("Nose_" .. i, Vector3.new(0.9, math.max(d, 0.3), math.max(d, 0.3)), CFrame.new(0, 0, -3 - (i - 0.5) * 0.9) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(210, 70, 60), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	end
	for i = 1, 3 do
		local a = math.rad(i * 120)
		local fin = Instance.new("WedgePart")
		fin.Name = "Fin_" .. i
		fin.Size = Vector3.new(0.3, 1.6, 1.6)
		fin.Color = Color3.fromRGB(220, 70, 60)
		fin.Material = Enum.Material.SmoothPlastic
		fin.Anchored = true
		fin.CanCollide = false
		fin.CFrame = root.CFrame * CFrame.new(math.cos(a) * 1.1, math.sin(a) * 1.1, 2.4) * CFrame.Angles(0, 0, a)
		fin.Parent = model
	end

	local front = Instance.new("Attachment")
	front.Position = Vector3.new(0, 0, -2)
	front.Parent = root
	local back = Instance.new("Attachment")
	back.Position = Vector3.new(0, 0, 3)
	back.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = front
	trail.Attachment1 = back
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 205, 70), Color3.fromRGB(235, 75, 35))
	trail.Lifetime = 0.35
	trail.MinLength = 0.4
	trail.Parent = root

	local light = Instance.new("PointLight")
	light.Brightness = 8
	light.Range = 20
	light.Color = Color3.fromRGB(255, 120, 20)
	light.Parent = root

	return model
end

local function arcPos(origin, target, t)
	local straight = origin:Lerp(target, t)
	local height = math.sin(t * math.pi) * Config.ROCKET_ARC
	return Vector3.new(straight.X, straight.Y + height, straight.Z)
end

-- Спавнит ракету, ведёт её по баллистической дуге на сервере, просит клиента
-- стрелка вести камеру за этим инстансом, затем вызывает onImpact в точке удара.
local function flyRocket(shooter, originPos, targetPos, onImpact)
	local model = buildFlyingRocket(originPos)
	model.Parent = workspace

	-- Клиенту-стрелку сообщаем, какую ракету вести камерой.
	if shooter and shooter.Parent then
		Remotes.Get("RocketFollow"):FireClient(shooter, model, targetPos)
	end

	task.spawn(function()
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

local function createOwnedLaunchers(player)
	launcherReady[player] = launcherReady[player] or {}
	for index = 1, DataManager.GetLauncherCount(player) do
		PlotManager.CreateLauncher(player, index)
		launcherReady[player][index] = launcherReady[player][index] or 0
	end
	sendRocketState(player)
end

local function takeReadyLauncher(player)
	local now = workspace:GetServerTimeNow()
	for index = 1, DataManager.GetLauncherCount(player) do
		if (launcherReady[player] and launcherReady[player][index] or 0) <= now then
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
	game:GetService("Players").PlayerAdded:Connect(setupPlayer)
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		launcherReady[player] = nil
		lastRequest[player] = nil
	end)
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do setupPlayer(player) end

	Remotes.Get("BuyLauncher").OnServerEvent:Connect(function(player)
		local success, result = DataManager.BuyNextLauncher(player)
		if not success then notify(player, result, "error") return end
		launcherReady[player] = launcherReady[player] or {}
		launcherReady[player][result] = 0
		PlotManager.CreateLauncher(player, result)
		sendRocketState(player)
		notify(player, string.format("Установка %d построена", result), "success")
	end)

	-- Клиент шлёт целевой остров и (опционально) точную точку прицела (raycast по 3D-миру).
	launchEvent.OnServerEvent:Connect(function(player, targetPlotId, targetPos)
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

		local launcherIndex = takeReadyLauncher(player)
		if not launcherIndex then
			notify(player, "Все ракеты перезаряжаются", "error")
			return
		end
		local originPos = PlotManager.GetLauncherOrigin(player, launcherIndex)
		if not originPos then return end

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

		flyRocket(player, originPos, impactPos, function()
			-- Авторитетный прилёт: урон/оглушение зданий считает сервер.
			local destroyed = FarmManager.ApplyRocketImpact(targetPlotId, impactPos, Config.ROCKET_DAMAGE)
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