-- PlotManager.luau — генерация участков и назначение игрокам
local Players= game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config            = require(ReplicatedStorage.Shared.Config)

local PlotManager = {}

-- plots[plotId] = { owner=Player|nil, model=Model, padPart=Part, center=Vector3 }
local plots = {}
local playerPlot = {}   -- player → plotId

local PLOT_COLORS = {
	Color3.fromRGB(220, 100, 80),
	Color3.fromRGB(80, 140, 220),
	Color3.fromRGB(80, 200, 100),
	Color3.fromRGB(220, 180, 50),
	Color3.fromRGB(180, 80, 220),
	Color3.fromRGB(60, 200, 200),
}

-- Создаёт визуальную модель участка в Workspace
local function buildPlot(plotId, position)
	local folder = Instance.new("Folder")
	folder.Name  = "Plot_" .. plotId
	folder.Parent = workspace

	-- Плита участка
	local pad = Instance.new("Part")
	pad.Name      = "Pad"
	pad.Anchored  = true
	pad.Size      = Vector3.new(Config.PLOT_SIZE, 1, Config.PLOT_SIZE)
	pad.Position  = position + Vector3.new(0, 0.5, 0)
	pad.Color     = PLOT_COLORS[plotId] or Color3.fromRGB(200,200,200)
	pad.Material  = Enum.Material.SmoothPlastic
	pad.Parent    = folder

	-- Табличка владельца (BillboardGui)
	local sign = Instance.new("Part")
	sign.Name     = "Sign"
	sign.Anchored = true
	sign.Size     = Vector3.new(6, 2, 0.4)
	sign.Position = position + Vector3.new(0, 8, -Config.PLOT_SIZE / 2 + 2)
	sign.Color    = Color3.fromRGB(40, 40, 40)
	sign.Material = Enum.Material.SmoothPlastic
	sign.Parent   = folder

	local bb = Instance.new("BillboardGui")
	bb.Size= UDim2.new(0, 200, 0, 60)
	bb.StudsOffset   = Vector3.new(0, 1, 0)
	bb.AlwaysOnTop   = false
	bb.Parent        = sign

	local label = Instance.new("TextLabel")
	label.Size= UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text            = "Свободно"
	label.TextColor3      = Color3.fromRGB(255, 255, 255)
	label.TextScaled      = true
	label.Font            = Enum.Font.GothamBold
	label.Parent          = bb

	-- Спавн на участке
	local spawn = Instance.new("SpawnLocation")
	spawn.Name     = "PlotSpawn"
	spawn.Anchored = true
	spawn.Size     = Vector3.new(6, 1, 6)
	spawn.Position = position + Vector3.new(0, 1.5, 20)
	spawn.Neutral  = false
	spawn.TeamColor = BrickColor.new("White")
	spawn.Parent   = folder

	plots[plotId] = {
		owner    = nil,
		folder   = folder,
		pad      = pad,
		label    = label,
		spawn    = spawn,
		center   = position,
	}
end

function PlotManager.Init()
	-- Генерируем участки
	for i, pos in ipairs(Config.PLOT_POSITIONS) do
		buildPlot(i, pos)
	end

	Players.PlayerAdded:Connect(function(player)
		-- Назначаем первый свободный участок
		task.wait(1)
		for id, plot in pairs(plots) do
			if plot.owner == nil then
				plot.owner = player
				playerPlot[player] = id
				plot.label.Text = player.Name
				player.RespawnLocation = plot.spawn
				print("[PlotManager] " .. player.Name .. " → участок " .. id)
				break
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local id = playerPlot[player]
		if id then
			local plot = plots[id]
			if plot then
				plot.owner = nil
				plot.label.Text = "Свободно"
			end
			playerPlot[player] = nil
		end
	end)
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