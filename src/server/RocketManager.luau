-- RocketManager.luau — обработка запуска ракет
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config            = require(ReplicatedStorage.Shared.Config)
local Remotes           = require(ReplicatedStorage.Shared.Remotes)
local DataManager       = require(script.Parent.DataManager)
local PlotManager       = require(script.Parent.PlotManager)
local FarmManager       = require(script.Parent.FarmManager)

local RocketManager = {}

function RocketManager.Init()
	local launchEvent = Remotes.Get("LaunchRocket")
	local firedEvent  = Remotes.Get("RocketFired")

	launchEvent.OnServerEvent:Connect(function(player, targetPlotId)
		-- Валидация
		if type(targetPlotId) ~= "number" then return end

		local targetPlot = PlotManager.GetPlot(targetPlotId)
		if not targetPlot then return end

		-- Нельзя атаковать свой участок
		local myPlotId = select(1, PlotManager.GetPlotByPlayer(player))
		if myPlotId == targetPlotId then return end

		-- Проверяем наличие ракеты
		if not DataManager.UseRocket(player) then return end

		-- Откуда летит ракета — центр фермы игрока
		local originPos
		if myPlotId then
			originPos = FarmManager.GetFarmCenter(myPlotId)
		else
			-- Если участка нет — от персонажа
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			originPos = root and root.Position or Vector3.new(0, 10, 0)
		end

		local targetPos = FarmManager.GetFarmCenter(targetPlotId)

		-- Наносим урон немедленно (сервер авторитетен)
		local destroyed = FarmManager.DamageAtPlot(targetPlotId, Config.ROCKET_DAMAGE)

		-- Сообщаем всем клиентам: запустить анимацию
		firedEvent:FireAllClients({
			shooterName= player.Name,
			originPos     = originPos,
			targetPos     = targetPos,
			targetPlotId  = targetPlotId,
			destroyed     = destroyed,
		})
	end)
end

return RocketManager