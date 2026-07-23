-- HudManager.luau — деньги (внизу по центру), настройки (⚙ справа снизу)
-- и сценарий ракетного удара. НИКАКИХ текстовых плашек по центру экрана:
-- ошибки показываются красной вспышкой денежного счётчика, подсказки прицела —
-- одной строкой под верхней плашкой во время прицеливания.
--
-- Сценарий запуска (без бокового меню):
--   1. Игрок подходит к своей установке и удерживает E (ProximityPrompt).
--   2. Камера СРАЗУ переносится к первому вражескому острову.
--   3. A / D (или стрелки ◀ ▶ сверху, между ними — ник владельца) листают острова.
--   4. Клик по острову ставит маркер удара, кнопка «ЗАПУСК» внизу отправляет ракету.
--   5. Выход — кнопка ✕ или клавиша Q.
-- Сервер независимо проверяет дистанцию, права, остров и точку — клиенту не доверяем.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local sharedFolder      = ReplicatedStorage:WaitForChild("Shared", 10)

local Remotes           = require(sharedFolder:WaitForChild("Remotes"))
local Config            = require(sharedFolder:WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

local HudManager = {}

local animEnabled = true
local rocketReady = Config.START_LAUNCHERS

-- Деньги (нижняя панель)
local moneyText, moneyStroke, moneyLogoScale
local shownMoney = 0
local moneyThread, moneyPopTween
local flashToken = 0

-- Настройки (шестерёнка)
local settingsPanel, animToggleBtn

-- Состояние сценария прицеливания.
local topBar, ownerLabel, islandLabel, hintLabel, launchButton
local targetingActive = false
local targets = {}      -- { {plotId, ownerUserId}, ... }
local targetIndex = 0
local aimPos = nil
local aimMarker = nil

-- Заморозка передвижения на время прицеливания (камера уходит к цели).
local humFrozen = false
local savedJumpPower, savedJumpHeight

-- Сохранённое состояние камеры для восстановления после прицеливания.
local cameraFocused = false
local savedCameraType, savedCameraSubject

local GOLD_TEXT = Color3.fromRGB(255, 227, 125)
local GOLD_STROKE = Color3.fromRGB(255, 214, 90)

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

-- Вспышка денежного счётчика вместо текстовых уведомлений: красная — ошибка
-- (не хватает денег и т.п.), зелёная — успех. Никаких плашек по центру экрана.
function HudManager.FlashFeedback(kind)
	if not moneyText then return end
	flashToken += 1
	local token = flashToken
	local color = kind == "error" and Color3.fromRGB(255, 90, 80) or Color3.fromRGB(120, 235, 150)
	moneyText.TextColor3 = color
	if moneyStroke then
		moneyStroke.Color = color
		moneyStroke.Transparency = 0.2
	end
	task.delay(0.5, function()
		if flashToken ~= token then return end
		if moneyText then moneyText.TextColor3 = GOLD_TEXT end
		if moneyStroke then
			moneyStroke.Color = GOLD_STROKE
			moneyStroke.Transparency = 0.72
		end
	end)
end

-- Совместимость со старым API: текстовых уведомлений больше нет.
function HudManager.ShowNotification(_text, _color)
	HudManager.FlashFeedback("error")
end

-- Подсказка прицела (видна только во время прицеливания, под верхней плашкой).
local function setHint(text, color)
	if hintLabel and hintLabel.Visible then
		hintLabel.Text = text
		hintLabel.TextColor3 = color or Color3.fromRGB(255, 214, 90)
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
	local target = CFrame.lookAt(center + Vector3.new(0, 340, 150), center)
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
			savedJumpPower = hum.JumpPower
			savedJumpHeight = hum.JumpHeight
			humFrozen = true
		end
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.JumpHeight = 0
	elseif humFrozen then
		-- Возвращаем скорость с учётом спринта (Shift может быть зажат прямо сейчас).
		local sprinting = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
		hum.WalkSpeed = sprinting and Config.SPRINT_SPEED or Config.WALK_SPEED
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
	launchButton.BackgroundColor3 = enabled and Color3.fromRGB(205, 67, 55) or Color3.fromRGB(60, 66, 74)
	launchButton.TextColor3 = enabled and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 158, 166)
end

-- Полное закрытие сценария: панели, маркер, камера, заморозка.
function HudManager.CloseTargeting()
	targetingActive = false
	targetIndex = 0
	aimPos = nil
	clearMarker()
	restoreCamera()
	setFrozen(false)
	if topBar then topBar.Visible = false end
	if hintLabel then hintLabel.Visible = false end
	if launchButton then launchButton.Visible = false end
end

-- Список допустимых островов-целей (все, кроме своего). Занятые — первыми.
local function collectTargets()
	local myId = player:GetAttribute("PlotId")
	local entries = {}
	for _, folder in ipairs(workspace:GetChildren()) do
		local pid = folder:GetAttribute("PlotId")
		if pid ~= nil and pid ~= myId then
			table.insert(entries, { plotId = pid, ownerUserId = folder:GetAttribute("OwnerUserId") or 0 })
		end
	end
	table.sort(entries, function(a, b)
		local ao, bo = a.ownerUserId ~= 0, b.ownerUserId ~= 0
		if ao ~= bo then return ao end
		return a.plotId < b.plotId
	end)
	return entries
end

-- Верхняя плашка: ◀ [ник владельца острова] ▶
local function updateHeader()
	local entry = targets[targetIndex]
	if not entry then return end
	local folder = workspace:FindFirstChild("Plot_" .. entry.plotId)
	local ownerUserId = folder and folder:GetAttribute("OwnerUserId") or 0
	local ownerName = "Свободный остров"
	if ownerUserId ~= 0 then
		local p = Players:GetPlayerByUserId(ownerUserId)
		ownerName = p and p.DisplayName or ("Игрок " .. ownerUserId)
	end
	if ownerLabel then
		ownerLabel.Text = ownerName
		ownerLabel.TextColor3 = ownerUserId ~= 0 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 175, 182)
	end
	if islandLabel then
		islandLabel.Text = string.format("Остров #%d   •   %d / %d", entry.plotId, targetIndex, #targets)
	end
end

-- Переключение на цель под номером index (с закольцовкой).
local function selectTarget(index)
	if #targets == 0 then return end
	targetIndex = ((index - 1) % #targets) + 1
	aimPos = nil
	clearMarker()
	setLaunchEnabled(false)
	if hintLabel then
		hintLabel.Text = "Кликните по острову — точка удара   •   A / D — сменить остров   •   Q — выход"
		hintLabel.TextColor3 = Color3.fromRGB(255, 214, 90)
	end
	updateHeader()
	focusCameraOnIsland(targets[targetIndex].plotId)
end

-- Открыть сценарий (вызывается ProximityPrompt'ом рядом с установкой).
-- Никаких списков: камера сразу уходит на первый вражеский остров.
function HudManager.OpenTargeting()
	if targetingActive then return end
	if player:GetAttribute("PlotId") == nil then return end
	targets = collectTargets()
	if #targets == 0 then
		HudManager.FlashFeedback("error")
		return
	end
	targetingActive = true
	aimPos = nil
	clearMarker()
	setFrozen(true)
	setLaunchEnabled(false)
	if topBar then topBar.Visible = true end
	if hintLabel then hintLabel.Visible = true end
	if launchButton then launchButton.Visible = true end
	selectTarget(1)
end

-- Подтверждение запуска: вызываем серверную логику с правильными аргументами.
local function doLaunch()
	if not targetingActive or targetIndex == 0 then return end
	local entry = targets[targetIndex]
	if not entry then return end
	if not aimPos then
		setHint("Сначала выберите точку удара — кликните по острову", Color3.fromRGB(255, 180, 40))
		return
	end
	if rocketReady <= 0 then
		setHint("Все ракеты перезаряжаются", Color3.fromRGB(255, 110, 95))
		HudManager.FlashFeedback("error")
		return
	end
	local plotId, pos = entry.plotId, aimPos
	-- Сначала закрываем UI/восстанавливаем камеру — затем сервер перехватит камеру
	-- под облёт ракеты (RocketFollow), стартовав с обычной камеры игрока.
	HudManager.CloseTargeting()
	Remotes.Get("LaunchRocket"):FireServer(plotId, pos)
end

-- Клик по 3D-миру в режиме прицела: ставим/переставляем маркер удара.
local function onWorldClick(input, gpe)
	if gpe then return end
	if not targetingActive or targetIndex == 0 then return end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	local entry = targets[targetIndex]
	if not entry then return end
	local part = mouse.Target
	if not part then return end
	local plotId = findClickedPlot(part)
	if plotId ~= entry.plotId then
		setHint("Кликните по выбранному острову", Color3.fromRGB(255, 180, 40))
		return
	end
	aimPos = mouse.Hit.Position
	showMarker(aimPos)
	setLaunchEnabled(true)
	setHint("Точка удара выбрана — жмите ЗАПУСК", Color3.fromRGB(98, 220, 144))
end

-- Создаёт ProximityPrompt на КАЖДОЙ своей установке.
local function ensurePrompts()
	local myId = player:GetAttribute("PlotId")
	if myId == nil then return end
	local plotFolder = workspace:FindFirstChild("Plot_" .. myId)
	local silo = plotFolder and plotFolder:FindFirstChild("RocketSilo")
	if not silo then return end
	for _, launcher in ipairs(silo:GetChildren()) do
		if launcher:IsA("Model") and not launcher:FindFirstChild("LaunchPrompt", true) then
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

-- Красивое число с разделением тысяч: 1234567 → "1 234 567".
local function formatMoney(n)
	local s = tostring(math.floor((n or 0) + 0.5))
	local formatted = (s:reverse():gsub("(%d%d%d)", "%1 ")):reverse()
	return (formatted:gsub("^%s+", ""))
end

function HudManager.Init(initAnimEnabled)
	animEnabled = initAnimEnabled ~= false

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TycoonHud"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	screenGui.Parent = playerGui

	-- === Деньги: внизу, горизонтально по центру, слева круглый логотип бакса ===
	local moneyBar = makeFrame(screenGui, UDim2.new(0, 230, 0, 56), UDim2.new(0.5, -115, 1, -72), Color3.fromRGB(14, 18, 24), 0.08, "MoneyBar")
	moneyBar:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 28)
	moneyStroke = Instance.new("UIStroke")
	moneyStroke.Color = GOLD_STROKE
	moneyStroke.Transparency = 0.72
	moneyStroke.Thickness = 1.4
	moneyStroke.Parent = moneyBar

	-- Якорь по центру: масштабирование «пульса» идёт от центра, логотип всегда
	-- отцентрован по вертикали (раньше при прокачке он «уезжал» вниз).
	local logo = Instance.new("Frame")
	logo.Name = "DollarLogo"
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Size = UDim2.new(0, 40, 0, 40)
	logo.Position = UDim2.new(0, 28, 0.5, 0)
	logo.BackgroundColor3 = Color3.fromRGB(52, 206, 118)
	logo.BorderSizePixel = 0
	logo.Parent = moneyBar
	local logoCorner = Instance.new("UICorner")
	logoCorner.CornerRadius = UDim.new(1, 0)
	logoCorner.Parent = logo
	moneyLogoScale = Instance.new("UIScale")
	moneyLogoScale.Parent = logo

	local dollar = makeLabel(logo, "$", UDim2.new(1, 0, 1, 0), UDim2.new(), Color3.fromRGB(255, 255, 255), 24, Enum.Font.GothamBlack)
	dollar.TextXAlignment = Enum.TextXAlignment.Center

	moneyText = makeLabel(moneyBar, "0", UDim2.new(1, -66, 1, 0), UDim2.new(0, 58, 0, 0), GOLD_TEXT, 22, Enum.Font.GothamBold)
	moneyText.TextXAlignment = Enum.TextXAlignment.Left
	moneyText.TextYAlignment = Enum.TextYAlignment.Center

	-- === Шестерёнка настроек (правый нижний угол) ===
	local gearBtn = makeButton(screenGui, "⚙️", UDim2.new(0, 46, 0, 46), UDim2.new(1, -58, 1, -58), Color3.fromRGB(22, 28, 36))
	gearBtn:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(1, 0)
	gearBtn.TextSize = 22

	settingsPanel = makeFrame(screenGui, UDim2.new(0, 264, 0, 64), UDim2.new(1, -276, 1, -130), Color3.fromRGB(14, 18, 24), 0.06, "SettingsPanel")
	settingsPanel:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 14)
	settingsPanel.Visible = false

	makeLabel(settingsPanel, "Анимация полёта ракеты", UDim2.new(1, -102, 1, 0), UDim2.new(0, 14, 0, 0), Color3.fromRGB(218, 226, 232), 14)

	animToggleBtn = makeButton(settingsPanel, "ВКЛ", UDim2.new(0, 74, 0, 34), UDim2.new(1, -84, 0.5, -17), Color3.fromRGB(52, 190, 110))
	local function refreshToggle()
		animToggleBtn.Text = animEnabled and "ВКЛ" or "ВЫКЛ"
		animToggleBtn.BackgroundColor3 = animEnabled and Color3.fromRGB(52, 190, 110) or Color3.fromRGB(90, 98, 108)
	end
	refreshToggle()

	gearBtn.MouseButton1Click:Connect(function()
		settingsPanel.Visible = not settingsPanel.Visible
	end)
	animToggleBtn.MouseButton1Click:Connect(function()
		animEnabled = not animEnabled
		refreshToggle()
		-- Сохраняется НАВСЕГДА (DataStore на сервере, см. DataManager).
		Remotes.Get("SetAnimSetting"):FireServer(animEnabled)
	end)

	-- === Верхняя плашка прицеливания: ◀ [ник] ▶ и ✕ ===
	topBar = makeFrame(screenGui, UDim2.new(0, 460, 0, 68), UDim2.new(0.5, -230, 0, 14), Color3.fromRGB(14, 18, 24), 0.12, "TargetBar")
	topBar:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 16)
	topBar.Visible = false

	local prevBtn = makeButton(topBar, "◀", UDim2.new(0, 52, 1, -16), UDim2.new(0, 8, 0, 8), Color3.fromRGB(36, 44, 52))
	prevBtn.TextSize = 22
	local nextBtn = makeButton(topBar, "▶", UDim2.new(0, 52, 1, -16), UDim2.new(1, -60, 0, 8), Color3.fromRGB(36, 44, 52))
	nextBtn.TextSize = 22

	ownerLabel = makeLabel(topBar, "—", UDim2.new(1, -140, 0, 30), UDim2.new(0, 70, 0, 8), Color3.fromRGB(255, 255, 255), 20, Enum.Font.GothamBold)
	ownerLabel.TextXAlignment = Enum.TextXAlignment.Center
	islandLabel = makeLabel(topBar, "", UDim2.new(1, -140, 0, 20), UDim2.new(0, 70, 0, 40), Color3.fromRGB(160, 175, 182), 13)
	islandLabel.TextXAlignment = Enum.TextXAlignment.Center

	-- ✕ прижата к правому верхнему углу плашки (снаружи)
	local closeBtn = makeButton(topBar, "✕", UDim2.new(0, 34, 0, 34), UDim2.new(1, 10, 0, 0), Color3.fromRGB(73, 82, 86))

	prevBtn.MouseButton1Click:Connect(function() selectTarget(targetIndex - 1) end)
	nextBtn.MouseButton1Click:Connect(function() selectTarget(targetIndex + 1) end)
	closeBtn.MouseButton1Click:Connect(function() HudManager.CloseTargeting() end)

	-- Подсказка под плашкой
	hintLabel = makeLabel(screenGui, "", UDim2.new(0, 680, 0, 22), UDim2.new(0.5, -340, 0, 88), Color3.fromRGB(255, 214, 90), 14)
	hintLabel.TextXAlignment = Enum.TextXAlignment.Center
	hintLabel.Visible = false

	-- Большая кнопка запуска (над денежной панелью)
	launchButton = makeButton(screenGui, "🚀  ЗАПУСК", UDim2.new(0, 260, 0, 58), UDim2.new(0.5, -130, 1, -148), Color3.fromRGB(60, 66, 74))
	launchButton:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0, 29)
	launchButton.TextSize = 20
	launchButton.Visible = false
	launchButton.Active = false
	launchButton.AutoButtonColor = false
	launchButton.MouseButton1Click:Connect(doLaunch)

	-- Ввод: клики мыши ставят точку удара; A/D/стрелки листают острова; Q — выход.
	UserInputService.InputBegan:Connect(function(input, gpe)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			onWorldClick(input, gpe)
			return
		end
		if gpe then return end
		if not targetingActive then return end
		if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			selectTarget(targetIndex - 1)
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			selectTarget(targetIndex + 1)
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Escape then
			HudManager.CloseTargeting()
		end
	end)

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

	-- Обновляем цели при входе/выходе игроков, пока прицел открыт (текущий остров сохраняем).
	local function maybeRefresh()
		task.wait(0.4)
		if not targetingActive then return end
		local currentPlotId = targets[targetIndex] and targets[targetIndex].plotId
		targets = collectTargets()
		if #targets == 0 then
			HudManager.CloseTargeting()
			return
		end
		local newIndex = 1
		for i, entry in ipairs(targets) do
			if entry.plotId == currentPlotId then
				newIndex = i
				break
			end
		end
		targetIndex = newIndex
		updateHeader()
	end
	Players.PlayerAdded:Connect(maybeRefresh)
	Players.PlayerRemoving:Connect(maybeRefresh)

	-- Поддержка prompt'ов и проверка валидности прицела (исчезновение установки).
	task.spawn(function()
		while true do
			ensurePrompts()
			if targetingActive and not targetingStillValid() then
				HudManager.CloseTargeting()
				HudManager.FlashFeedback("error")
			end
			task.wait(1)
		end
	end)
end

function HudManager.UpdateData(data)
	local target = data.money or 0
	if not moneyText then return end

	-- Плавный "отсчёт" суммы + пульс логотипа при изменении.
	if moneyThread then task.cancel(moneyThread) end
	local from = shownMoney
	if from ~= target and moneyLogoScale then
		-- Гасим предыдущий пульс и сбрасываем масштаб: незавершённый твин
		-- оставлял Scale > 1 и логотип «уезжал» из центра.
		if moneyPopTween then moneyPopTween:Cancel() end
		moneyLogoScale.Scale = 1
		moneyPopTween = TweenService:Create(moneyLogoScale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Scale = 1.15 })
		moneyPopTween:Play()
	end
	moneyThread = task.spawn(function()
		local t0 = os.clock()
		local duration = 0.4
		while true do
			local a = math.min((os.clock() - t0) / duration, 1)
			local v = math.floor(from + (target - from) * a + 0.5)
			shownMoney = v
			moneyText.Text = formatMoney(v)
			if a >= 1 then break end
			RunService.RenderStepped:Wait()
		end
	end)
end

function HudManager.UpdateRocketState(data)
	rocketReady = data.ready or 0
end

function HudManager.IsAnimEnabled()
	return animEnabled
end

return HudManager
