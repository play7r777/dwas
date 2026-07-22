-- HudManager.luau - экономика, статус установок и полный сценарий ракетного удара.
--
-- Сценарий запуска (см. также RocketManager на сервере):
--   1. Игрок подходит к своей ракетной установке и удерживает E (ProximityPrompt).
--   2. Открывается панель "РАКЕТНЫЙ УДАР" со списком допустимых островов-целей.
--   3. Выбор острова наводит камеру на него и включает выбор точки удара кликом.
--   4. Клик по острову ставит маркер удара; точку можно переставить или отменить.
--   5. Кнопка "ЗАПУСК" шлёт LaunchRocket(targetPlotId, targetPos) на сервер.
-- Сервер независимо проверяет дистанцию, права, остров и точку — клиенту не доверяем.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Remotes           = require(sharedFolder:WaitForChild("Remotes"))
local Config            = require(sharedFolder:WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

local HudManager = {}

local animEnabled = true
local moneyLabel, rocketLabel, buyRocketBtn
local launcherCount = Config.START_LAUNCHERS
local rocketReady = Config.START_LAUNCHERS
local notifFrame, notifLabel, notifThread

-- Состояние сценария прицеливания.
local targetPanel, listView, aimView, listScroll
local aimInfoLabel, aimStatusLabel, launchButton
local targetingActive = false
local aimingPlotId = nil
local aimPos = nil
local aimMarker = nil

-- Заморозка передвижения на время прицеливания (камера уходит к цели).
local humFrozen = false
local savedWalkSpeed, savedJumpPower, savedJumpHeight

-- Сохранённое состояние камеры для восстановления после прицеливания.
local cameraFocused = false
local savedCameraType, savedCameraSubject

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

-- Идём вверх по иерархии клика до папки острова (у неё есть атрибут PlotId).
local function findClickedPlot(part)
	local current = part
	while current and current ~= workspace do
		if current:GetAttribute("PlotId") ~= nil then
			return current:GetAttribute("PlotId")
		end
		current = current.Parent
	end
	return nil
end

-- === Маркер точки удара (только визуальный, локальный клиенту) ===
local function ensureMarker()
	if aimMarker and aimMarker.Parent then return aimMarker end
	local m = Instance.new("Model")
	m.Name = "RocketAimMarker"

	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 70, 55)
	beam.Transparency = 0.25
	beam.Size = Vector3.new(60, 2, 2)
	beam.Parent = m

	local ring = Instance.new("Part")
	ring.Name = "Ring"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(255, 120, 60)
	ring.Transparency = 0.15
	ring.Size = Vector3.new(1, 16, 16)
	ring.Parent = m

	aimMarker = m
	return m
end

local function showMarker(pos)
	local m = ensureMarker()
	-- Цилиндры лежат вдоль локального X; поворот на 90° по Z ставит их вертикально.
	m.Beam.CFrame = CFrame.new(pos + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90))
	m.Ring.CFrame = CFrame.new(pos + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	m.Parent = workspace
end

local function clearMarker()
	if aimMarker then aimMarker.Parent = nil end
end

-- === Камера: обзор выбранного острова сверху под углом ===
local function focusCameraOnIsland(plotId)
	local center = Config.PLOT_POSITIONS[plotId]
	if not center then return end
	local camera = workspace.CurrentCamera
	if not camera then return end
	if not cameraFocused then
		savedCameraType = camera.CameraType
		savedCameraSubject = camera.CameraSubject
		cameraFocused = true
	end
	camera.CameraType = Enum.CameraType.Scriptable
	local target = CFrame.lookAt(center + Vector3.new(0, 300, 120), center)
	TweenService:Create(camera, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = target,
	}):Play()
end

local function restoreCamera()
	if not cameraFocused then return end
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = savedCameraType or Enum.CameraType.Custom
		if savedCameraSubject then camera.CameraSubject = savedCameraSubject end
	end
	cameraFocused = false
end

-- === Заморозка/разморозка передвижения ===
local function setFrozen(on)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	if on then
		if not humFrozen then
			savedWalkSpeed = hum.WalkSpeed
			savedJumpPower = hum.JumpPower
			savedJumpHeight = hum.JumpHeight
			humFrozen = true
		end
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
	elseif humFrozen then
		hum.WalkSpeed = savedWalkSpeed or 16
		hum.JumpPower = savedJumpPower or 0
		hum.JumpHeight = savedJumpHeight or 7.2
		humFrozen = false
	end
end

-- === Кнопка запуска: активна только когда выбрана точка удара ===
local function setLaunchEnabled(enabled)
	if not launchButton then return end
	launchButton.Active = enabled
	launchButton.AutoButtonColor = enabled
	launchButton.BackgroundColor3 = enabled and Color3.fromRGB(205, 67, 55) or Color3.fromRGB(73, 82, 86)
end

-- Полное закрытие сценария: панель, маркер, камера, заморозка.
function HudManager.CloseTargeting()
	targetingActive = false
	aimingPlotId = nil
	aimPos = nil
	clearMarker()
	restoreCamera()
	setFrozen(false)
	if targetPanel then targetPanel.Visible = false end
end

-- Список допустимых островов-целей (все, кроме своего). Владелец либо "свободно".
local function refreshIslandList()
	if not listScroll then return end
	for _, child in ipairs(listScroll:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local myId = player:GetAttribute("PlotId")
	local entries = {}
	for _, folder in ipairs(workspace:GetChildren()) do
		local pid = folder:GetAttribute("PlotId")
		if pid ~= nil and pid ~= myId then
			table.insert(entries, { plotId = pid, ownerUserId = folder:GetAttribute("OwnerUserId") or 0 })
		end
	end
	-- Занятые острова (реальные враги) — вверху списка, затем по номеру.
	table.sort(entries, function(a, b)
		local ao, bo = a.ownerUserId ~= 0, b.ownerUserId ~= 0
		if ao ~= bo then return ao end
		return a.plotId < b.plotId
	end)

	for i, entry in ipairs(entries) do
		local owned = entry.ownerUserId ~= 0
		local ownerName
		if owned then
			local p = Players:GetPlayerByUserId(entry.ownerUserId)
			ownerName = p and p.DisplayName or ("Игрок " .. entry.ownerUserId)
		else
			ownerName = "Свободный остров"
		end

		local card = makeFrame(listScroll, UDim2.new(1, -8, 0, 62), UDim2.new(), Color3.fromRGB(35, 42, 47), 0.08, "Island_" .. entry.plotId)
		card.LayoutOrder = i
		makeLabel(card, ownerName, UDim2.new(1, -16, 0, 22), UDim2.fromOffset(8, 5), owned and Color3.fromRGB(235, 239, 241) or Color3.fromRGB(150, 165, 170), 14, Enum.Font.GothamBold)
		makeLabel(card, "Остров #" .. entry.plotId, UDim2.new(1, -90, 0, 18), UDim2.fromOffset(8, 30), Color3.fromRGB(170, 185, 190), 12)
		local pick = makeButton(card, "Выбрать", UDim2.fromOffset(78, 26), UDim2.new(1, -86, 0, 28), owned and Color3.fromRGB(205, 67, 55) or Color3.fromRGB(90, 100, 108))
		local plotId = entry.plotId
		pick.MouseButton1Click:Connect(function()
			HudManager.SelectIsland(plotId)
		end)
	end

	if #entries == 0 then
		makeLabel(listScroll, "Нет доступных островов", UDim2.new(1, -8, 0, 24), UDim2.new(), Color3.fromRGB(170, 185, 190), 13)
	end
end

-- Переход к выбору точки на выбранном острове.
function HudManager.SelectIsland(plotId)
	if not targetingActive then return end
	aimingPlotId = plotId
	aimPos = nil
	clearMarker()
	setLaunchEnabled(false)

	local folder = workspace:FindFirstChild("Plot_" .. plotId)
	local ownerUserId = folder and folder:GetAttribute("OwnerUserId") or 0
	local ownerName = "Свободный остров"
	if ownerUserId ~= 0 then
		local p = Players:GetPlayerByUserId(ownerUserId)
		ownerName = p and p.DisplayName or ("Игрок " .. ownerUserId)
	end
	if aimInfoLabel then aimInfoLabel.Text = string.format("Цель: Остров #%d\n%s", plotId, ownerName) end
	if aimStatusLabel then
		aimStatusLabel.Text = "Кликните по острову, чтобы\nвыбрать точку удара"
		aimStatusLabel.TextColor3 = Color3.fromRGB(255, 214, 90)
	end

	if listView then listView.Visible = false end
	if aimView then aimView.Visible = true end
	focusCameraOnIsland(plotId)
end

-- Возврат к списку целей (сброс точки и камеры).
local function backToList()
	aimingPlotId = nil
	aimPos = nil
	clearMarker()
	restoreCamera()
	setLaunchEnabled(false)
	if aimView then aimView.Visible = false end
	if listView then listView.Visible = true end
	refreshIslandList()
end

-- Открыть сценарий (вызывается ProximityPrompt'ом рядом с установкой).
function HudManager.OpenTargeting()
	if targetingActive then return end
	if player:GetAttribute("PlotId") == nil then return end
	targetingActive = true
	aimingPlotId = nil
	aimPos = nil
	clearMarker()
	setFrozen(true)
	setLaunchEnabled(false)
	if targetPanel then targetPanel.Visible = true end
	if aimView then aimView.Visible = false end
	if listView then listView.Visible = true end
	refreshIslandList()
end

-- Подтверждение запуска: вызываем серверную логику с правильными аргументами.
local function doLaunch()
	if not targetingActive or not aimingPlotId then return end
	if not aimPos then
		HudManager.ShowNotification("Сначала выберите точку удара", Color3.fromRGB(255, 180, 40))
		return
	end
	if rocketReady <= 0 then
		HudManager.ShowNotification("Все ракеты перезаряжаются", Color3.fromRGB(239, 117, 91))
		return
	end
	local plotId, pos = aimingPlotId, aimPos
	-- Сначала закрываем UI/восстанавливаем камеру — затем сервер перехватит камеру
	-- под облёт ракеты (RocketFollow), стартовав с обычной камеры игрока.
	HudManager.CloseTargeting()
	Remotes.Get("LaunchRocket"):FireServer(plotId, pos)
end

-- Клик по 3D-миру в режиме выбора точки: ставим/переставляем маркер удара.
local function onWorldClick(input, gpe)
	if gpe then return end
	if not targetingActive or not aimingPlotId then return end
	if not (aimView and aimView.Visible) then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local part = mouse.Target
	if not part then return end
	local plotId = findClickedPlot(part)
	if plotId ~= aimingPlotId then
		HudManager.ShowNotification("Кликните по выбранному острову", Color3.fromRGB(255, 180, 40))
		return
	end
	aimPos = mouse.Hit.Position
	showMarker(aimPos)
	setLaunchEnabled(true)
	if aimStatusLabel then
		aimStatusLabel.Text = "Точка удара выбрана.\nМожно запускать."
		aimStatusLabel.TextColor3 = Color3.fromRGB(98, 220, 144)
	end
end

-- Создаёт ProximityPrompt на КАЖДОЙ своей установке (видит только владелец).
local function ensurePrompts()
	local myId = player:GetAttribute("PlotId")
	if myId == nil then return end
	local plotFolder = workspace:FindFirstChild("Plot_" .. myId)
	local silo = plotFolder and plotFolder:FindFirstChild("RocketSilo")
	if not silo then return end
	for _, launcher in ipairs(silo:GetChildren()) do
		if launcher:IsA("Model") and not launcher:FindFirstChild("LaunchPrompt") then
			local pad = launcher.PrimaryPart or launcher:FindFirstChild("Pad")
			if pad then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "LaunchPrompt"
				prompt.ActionText = "Запуск ракеты"
				prompt.ObjectText = "Ракетная установка"
				prompt.HoldDuration = 0.6
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = 16
				prompt.Parent = pad
				prompt.Triggered:Connect(function()
					HudManager.OpenTargeting()
				end)
			end
		end
	end
end

-- Прицел недействителен, если своя установка исчезла (напр. игрок сброшен с плота).
local function targetingStillValid()
	local myId = player:GetAttribute("PlotId")
	if myId == nil then return false end
	local plotFolder = workspace:FindFirstChild("Plot_" .. myId)
	local silo = plotFolder and plotFolder:FindFirstChild("RocketSilo")
	return silo ~= nil and #silo:GetChildren() > 0
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

	local actPanel = makeFrame(screenGui, UDim2.new(0, 230, 0, 96), UDim2.new(0, 12, 0, 125), Color3.fromRGB(20, 20, 30), 0.1, "ActPanel")

	buyRocketBtn = makeButton(actPanel, "Установка 2  $" .. Config.LAUNCHER_COSTS[2], UDim2.new(1, -16, 0, 38), UDim2.new(0, 8, 0, 8), Color3.fromRGB(33, 133, 151))
	buyRocketBtn.MouseButton1Click:Connect(function()
		Remotes.Get("BuyLauncher"):FireServer()
	end)

	makeLabel(actPanel, "Подойди к ракете и держи E,\nчтобы нанести удар", UDim2.new(1, -16, 0, 34), UDim2.new(0, 8, 0, 54), Color3.fromRGB(170, 185, 190), 12).TextYAlignment = Enum.TextYAlignment.Top

	-- Панель ракетного удара (список целей + выбор точки). Скрыта по умолчанию.
	targetPanel = makeFrame(screenGui, UDim2.new(0, 270, 0, 420), UDim2.new(1, -282, 0, 12), Color3.fromRGB(20, 20, 30), 0.08, "TargetPanel")
	targetPanel.Visible = false

	makeLabel(targetPanel, "РАКЕТНЫЙ УДАР", UDim2.new(1, -46, 0, 26), UDim2.new(0, 10, 0, 6), Color3.fromRGB(236, 108, 91), 16, Enum.Font.GothamBold)

	local closeBtn = makeButton(targetPanel, "✕", UDim2.fromOffset(28, 24), UDim2.new(1, -34, 0, 6), Color3.fromRGB(73, 82, 86))
	closeBtn.MouseButton1Click:Connect(function()
		HudManager.CloseTargeting()
	end)

	-- --- Вид со списком островов ---
	listView = Instance.new("Frame")
	listView.Name = "ListView"
	listView.BackgroundTransparency = 1
	listView.Size = UDim2.new(1, 0, 1, -40)
	listView.Position = UDim2.new(0, 0, 0, 38)
	listView.Parent = targetPanel

	makeLabel(listView, "Выберите остров-цель:", UDim2.new(1, -16, 0, 20), UDim2.new(0, 10, 0, 2), Color3.fromRGB(200, 210, 214), 13)

	listScroll = Instance.new("ScrollingFrame")
	listScroll.Size = UDim2.new(1, -10, 1, -28)
	listScroll.Position = UDim2.new(0, 5, 0, 26)
	listScroll.BackgroundTransparency = 1
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 5
	listScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listScroll.CanvasSize = UDim2.new()
	listScroll.Parent = listView

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 8)
	layout.Parent = listScroll

	-- --- Вид выбора точки удара ---
	aimView = Instance.new("Frame")
	aimView.Name = "AimView"
	aimView.BackgroundTransparency = 1
	aimView.Size = UDim2.new(1, 0, 1, -40)
	aimView.Position = UDim2.new(0, 0, 0, 38)
	aimView.Visible = false
	aimView.Parent = targetPanel

	aimInfoLabel = makeLabel(aimView, "Цель: —", UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 0, 4), Color3.fromRGB(235, 239, 241), 15, Enum.Font.GothamBold)
	aimInfoLabel.TextYAlignment = Enum.TextYAlignment.Top

	aimStatusLabel = makeLabel(aimView, "Кликните по острову, чтобы\nвыбрать точку удара", UDim2.new(1, -20, 0, 44), UDim2.new(0, 10, 0, 52), Color3.fromRGB(255, 214, 90), 13)
	aimStatusLabel.TextYAlignment = Enum.TextYAlignment.Top

	launchButton = makeButton(aimView, "🚀 ЗАПУСК", UDim2.new(1, -20, 0, 46), UDim2.new(0, 10, 1, -108), Color3.fromRGB(73, 82, 86))
	launchButton.TextSize = 18
	launchButton.Active = false
	launchButton.AutoButtonColor = false
	launchButton.MouseButton1Click:Connect(doLaunch)

	local backButton = makeButton(aimView, "← К списку целей", UDim2.new(1, -20, 0, 40), UDim2.new(0, 10, 1, -54), Color3.fromRGB(50, 60, 68))
	backButton.MouseButton1Click:Connect(backToList)

	-- Клик по 3D-миру ставит точку удара в режиме прицела.
	UserInputService.InputBegan:Connect(onWorldClick)

	-- Смерть/респавн: сбрасываем прицел и любые изменения ввода/камеры.
	local function bindCharacter(char)
		humFrozen = false
		if targetingActive then HudManager.CloseTargeting() end
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 5)
		if hum then
			hum.Died:Connect(function()
				if targetingActive then HudManager.CloseTargeting() end
			end)
		end
	end
	player.CharacterAdded:Connect(bindCharacter)
	-- В отдельном потоке: bindCharacter может ждать Humanoid и не должен блокировать старт.
	if player.Character then task.spawn(bindCharacter, player.Character) end

	-- Обновляем список целей при входе/выходе игроков, пока открыт список.
	local function maybeRefresh()
		if targetingActive and listView and listView.Visible then
			task.wait(0.4)
			refreshIslandList()
		end
	end
	Players.PlayerAdded:Connect(maybeRefresh)
	Players.PlayerRemoving:Connect(maybeRefresh)

	-- Поддержка prompt'ов и проверка валидности прицела (исчезновение установки).
	task.spawn(function()
		while true do
			ensurePrompts()
			if targetingActive and not targetingStillValid() then
				HudManager.ShowNotification("Ракетная установка недоступна", Color3.fromRGB(239, 117, 91))
				HudManager.CloseTargeting()
			end
			task.wait(1)
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

function HudManager.IsAnimEnabled()
	return animEnabled
end

return HudManager
