-- HudManager.luau - compact economy, launcher status, and target controls
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Remotes           = require(sharedFolder:WaitForChild("Remotes"))
local Config            = require(sharedFolder:WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HudManager = {}

local animEnabled = true
local moneyLabel, rocketLabel, buyRocketBtn, aimBtn
local launcherCount = Config.START_LAUNCHERS
local rocketReady = Config.START_LAUNCHERS
local targetListFrame, targetPanel
local targetingMode = false
local notifFrame, notifLabel, notifThread

local function makeFrame(parent, size, pos, color, alpha, name)
	local f = Instance.new("Frame")
	f.Name = name or "Frame"
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color or Color3.fromRGB(25, 25, 35)
	f.BackgroundTransparency = alpha or 0.15
	f.BorderSizePixel = 0
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = f
	return f
end

local function makeLabel(parent, text, size, pos, color, fontSize, font)
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	l.TextSize = fontSize or 15
	l.Font = font or Enum.Font.GothamMedium
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function makeButton(parent, text, size, pos, bgColor, textColor)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = bgColor or Color3.fromRGB(50, 120, 220)
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
	b.TextSize = 14
	b.Font = Enum.Font.GothamBold
	b.AutoButtonColor = true
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	return b
end

function HudManager.ShowNotification(text, color)
	if notifLabel and notifFrame then
		notifLabel.Text = text
		notifLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255)
		notifFrame.Visible = true
		if notifThread then task.cancel(notifThread) end
		notifThread = task.delay(4.5, function()
			if notifFrame then notifFrame.Visible = false end
		end)
	end
end

local function getPlotForUser(userId)
	for _, folder in ipairs(workspace:GetChildren()) do
		if folder:GetAttribute("OwnerUserId") == userId then
			return folder, folder:GetAttribute("PlotId")
		end
	end
	return nil, nil
end

-- Список ЗАНЯТЫХ вражеских островов. Клик по «Огонь» бьёт по центру острова.
local function refreshTargets()
	if not targetListFrame then return end
	for _, child in ipairs(targetListFrame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then child:Destroy() end
	end

	local any = false
	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer == player then continue end
		local targetPlotFolder, targetPlotId = getPlotForUser(targetPlayer.UserId)
		if not targetPlotFolder or not targetPlotId then continue end
		any = true

		local card = makeFrame(targetListFrame, UDim2.new(1, -8, 0, 60), UDim2.new(), Color3.fromRGB(35, 42, 47), 0.08, targetPlayer.Name)
		makeLabel(card, targetPlayer.DisplayName, UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 5), Color3.fromRGB(235, 239, 241), 14, Enum.Font.GothamBold)
		makeLabel(card, "Остров #" .. targetPlotId, UDim2.new(1, -84, 0, 18), UDim2.fromOffset(8, 28), Color3.fromRGB(170, 185, 190), 12)
		local attack = makeButton(card, "Огонь", UDim2.fromOffset(66, 26), UDim2.new(1, -74, 0, 26), Color3.fromRGB(205, 67, 55))
		attack.MouseButton1Click:Connect(function()
			Remotes.Get("LaunchRocket"):FireServer(targetPlotId)
		end)
	end

	if not any then
		makeLabel(targetListFrame, "Нет активных врагов", UDim2.new(1, -8, 0, 24), UDim2.new(), Color3.fromRGB(170, 185, 190), 13)
	end
end

-- Идём вверх по иерархии клика до папки острова (у неё есть атрибут PlotId).
local function findClickedPlot(part)
	local current = part
	while current and current ~= workspace do
		if current:GetAttribute("PlotId") ~= nil then
			return current:GetAttribute("PlotId"), current:GetAttribute("OwnerUserId")
		end
		current = current.Parent
	end
	return nil, nil
end

-- В режиме прицела клик по ЛЮБОЙ точке вражеского острова задаёт точную цель (raycast).
local function setup3DClickTargeting()
	local mouse = player:GetMouse()
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if not targetingMode then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local targetPart = mouse.Target
			if not targetPart then return end
			local plotId, ownerUserId = findClickedPlot(targetPart)
			if plotId and ownerUserId and ownerUserId ~= 0 and ownerUserId ~= player.UserId then
				Remotes.Get("LaunchRocket"):FireServer(plotId, mouse.Hit.Position)
			end
		end
	end)
end

function HudManager.Init(initAnimEnabled)
	animEnabled = initAnimEnabled ~= false

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TycoonHud"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	screenGui.Parent = playerGui

	notifFrame = makeFrame(screenGui, UDim2.new(0, 360, 0, 50), UDim2.new(0.5, -180, 0, 10), Color3.fromRGB(20, 20, 25), 0.1, "NotifFrame")
	notifFrame.ZIndex = 20
	notifFrame.Visible = false

	notifLabel = makeLabel(notifFrame, "", UDim2.new(1, -10, 1, 0), UDim2.new(0, 5, 0, 0), Color3.fromRGB(255, 255, 255), 14, Enum.Font.GothamBold)
	notifLabel.TextXAlignment = Enum.TextXAlignment.Center

	local resPanel = makeFrame(screenGui, UDim2.new(0, 230, 0, 105), UDim2.new(0, 12, 0, 12), Color3.fromRGB(20, 20, 30), 0.1, "ResPanel")

	makeLabel(resPanel, "ROCKET ISLANDS", UDim2.new(1, -10, 0, 24), UDim2.new(0, 8, 0, 4), Color3.fromRGB(92, 205, 188), 16, Enum.Font.GothamBold)

	moneyLabel = makeLabel(resPanel, "Деньги  $0", UDim2.new(1, -10, 0, 22), UDim2.new(0, 8, 0, 32), Color3.fromRGB(255, 214, 90), 15)
	rocketLabel = makeLabel(resPanel, "Готово  1 / 1", UDim2.new(1, -10, 0, 22), UDim2.new(0, 8, 0, 56), Color3.fromRGB(98, 220, 144), 15)

	local actPanel = makeFrame(screenGui, UDim2.new(0, 230, 0, 100), UDim2.new(0, 12, 0, 125), Color3.fromRGB(20, 20, 30), 0.1, "ActPanel")

	buyRocketBtn = makeButton(actPanel, "Установка 2  $" .. Config.LAUNCHER_COSTS[2], UDim2.new(1, -16, 0, 38), UDim2.new(0, 8, 0, 8), Color3.fromRGB(33, 133, 151))
	buyRocketBtn.MouseButton1Click:Connect(function()
		Remotes.Get("BuyLauncher"):FireServer()
	end)

	-- Кнопка/клавиша E открывает UI выбора цели и включает прицел по 3D-миру.
	aimBtn = makeButton(actPanel, "Прицел (E)", UDim2.new(1, -16, 0, 38), UDim2.new(0, 8, 0, 54), Color3.fromRGB(205, 67, 55))
	aimBtn.MouseButton1Click:Connect(function()
		HudManager.SetTargeting(not targetingMode)
	end)

	targetPanel = makeFrame(screenGui, UDim2.new(0, 260, 0, 380), UDim2.new(1, -272, 0, 12), Color3.fromRGB(20, 20, 30), 0.1, "TargetPanel")
	targetPanel.Visible = false

	makeLabel(targetPanel, "ЦЕЛИ", UDim2.new(1, -10, 0, 26), UDim2.new(0, 8, 0, 4), Color3.fromRGB(236, 108, 91), 16, Enum.Font.GothamBold)

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size = UDim2.new(1, -10, 1, -36)
	scrollFrame.Position = UDim2.new(0, 5, 0, 32)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 5
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent = targetPanel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = scrollFrame

	targetListFrame = scrollFrame

	setup3DClickTargeting()

	-- Клавиша E открывает/закрывает выбор цели (не нужно стоять у ракеты).
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.E then
			HudManager.SetTargeting(not targetingMode)
		end
	end)

	Players.PlayerAdded:Connect(function() task.wait(1) refreshTargets() end)
	Players.PlayerRemoving:Connect(function() task.wait(1) refreshTargets() end)

	-- Слушаем изменения зданий для обновления списка целей
	local buildingState = Remotes.Get("BuildingStateChanged")
	buildingState.OnClientEvent:Connect(function()
		task.wait(0.5)
		refreshTargets()
	end)

	task.delay(1.5, refreshTargets)

	-- Регулярное обновление UI целей на случай если кто-то построился
	task.spawn(function()
		while true do
			task.wait(5)
			refreshTargets()
		end
	end)
end

function HudManager.UpdateData(data)
	if moneyLabel then moneyLabel.Text = "Деньги  $" .. (data.money or 0) end
	launcherCount = data.launchers or launcherCount
	if buyRocketBtn then
		if launcherCount >= Config.MAX_LAUNCHERS then
			buyRocketBtn.Text = "Все установки построены"
			buyRocketBtn.Active = false
			buyRocketBtn.BackgroundColor3 = Color3.fromRGB(73, 82, 86)
		else
			local nextCount = launcherCount + 1
			buyRocketBtn.Text = string.format("Установка %d  $%d", nextCount, Config.LAUNCHER_COSTS[nextCount])
			buyRocketBtn.Active = true
			buyRocketBtn.BackgroundColor3 = Color3.fromRGB(33, 133, 151)
		end
	end
end

function HudManager.UpdateRocketState(data)
	launcherCount = data.launchers or launcherCount
	rocketReady = data.ready or 0
	if rocketLabel then
		rocketLabel.Text = string.format("Готово  %d / %d", rocketReady, launcherCount)
		rocketLabel.TextColor3 = rocketReady > 0 and Color3.fromRGB(98, 220, 144) or Color3.fromRGB(239, 117, 91)
	end
end

function HudManager.SetTargeting(on)
	targetingMode = on and true or false
	if targetPanel then targetPanel.Visible = targetingMode end
	if aimBtn then
		aimBtn.Text = targetingMode and "Прицел ВКЛ (E)" or "Прицел (E)"
		aimBtn.BackgroundColor3 = targetingMode and Color3.fromRGB(120, 200, 255) or Color3.fromRGB(205, 67, 55)
	end
	if targetingMode then
		refreshTargets()
		HudManager.ShowNotification("Режим прицела: клик по вражескому острову. E — выкл", Color3.fromRGB(120, 200, 255))
	end
end

function HudManager.IsAnimEnabled()
	return animEnabled
end

return HudManager