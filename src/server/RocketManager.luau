-- RocketManager.luau - launcher purchases, reloads, and authoritative combat
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
	local firedEvent = Remotes.Get("RocketFired")

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

	launchEvent.OnServerEvent:Connect(function(player, targetPlotId, targetSlotIndex)
		local now = os.clock()
		if now - (lastRequest[player] or 0) < 0.2 then return end
		lastRequest[player] = now
		if type(targetPlotId) ~= "number" or targetPlotId % 1 ~= 0 then return end

		local targetPlot = PlotManager.GetPlot(targetPlotId)
		local myPlotId = select(1, PlotManager.GetPlotByPlayer(player))
		-- Можно бить по ЛЮБОМУ острову (в т.ч. пустому без владельца), кроме своего.
		if not targetPlot or myPlotId == targetPlotId then return end

		-- Цель по слоту опциональна: если задан живой слот — наносим урон,
		-- иначе прилёт в центр острова (только визуально).
		local slotIndex = nil
		if type(targetSlotIndex) == "number" and targetSlotIndex % 1 == 0
			and targetSlotIndex >= 1 and targetSlotIndex <= #Config.FARM_TYPES
			and FarmManager.IsSlotAlive(targetPlotId, targetSlotIndex) then
			slotIndex = targetSlotIndex
		end

		local launcherIndex = takeReadyLauncher(player)
		if not launcherIndex then
			notify(player, "Все ракеты перезаряжаются", "error")
			return
		end
		local originPos = PlotManager.GetLauncherOrigin(player, launcherIndex)
		if not originPos then return end

		local targetPos, destroyed
		if slotIndex then
			targetPos = FarmManager.GetSlotTargetPosition(targetPlotId, slotIndex)
			destroyed = FarmManager.DamageAtSlot(targetPlotId, slotIndex, Config.ROCKET_DAMAGE)
		else
			-- Прилёт в центр острова с небольшим случайным разбросом.
			targetPos = targetPlot.center + Vector3.new((math.random() - 0.5) * 30, 10, (math.random() - 0.5) * 30)
			destroyed = false
		end

		firedEvent:FireAllClients({
			shooterName = player.DisplayName,
			shooterUserId = player.UserId,
			originPos = originPos,
			targetPos = targetPos,
			targetPlotId = targetPlotId,
			targetSlotIndex = slotIndex,
			destroyed = destroyed,
		})
	end)
end

return RocketManager