-- HudManager.luau — весь UI: деньги, ракеты, цели, настройки
local Players= game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local Remotes           = require(ReplicatedStorage.Shared.Remotes)
local Config            = require(ReplicatedStorage.Shared.Config)

local player= Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HudManager = {}

local animEnabled = true
local moneyLabel, rocketLabel, upgradeBtn, buyRocketBtn
local targetListFrame, targetListLayout
local notifLabel

-- ─── Вспомогательные функции создания UI ──────────────────────────────────

local function makeFrame(parent, size, pos, color, alpha, name)
	local f = Instance.new("Frame")
	f.Name= name or "Frame"
	f.Size               = size
	f.Position           = pos
	f.BackgroundColor3   = color or Color3.fromRGB(30,30,30)
	f.BackgroundTransparency = alpha or 0.15
	f.BorderSizePixel    = 0
	f.Parent             = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = f
	return f
end

local function makeLabel(parent, text, size, pos, color, fontSize, font)
	local l = Instance.new("TextLabel")
	l.Size= size
	l.Position           = pos
	l.BackgroundTransparency = 1
	l.Text               = text
	l.TextColor3= color or Color3.fromRGB(255,255,255)
	l.TextSize           = fontSize or 16
	l.Font               = font or Enum.Font.GothamMedium
	l.TextXAlignment     = Enum.TextXAlignment.Left
	l.Parent             = parent
	return l
end

local function makeButton(parent, text, size, pos, bgColor, textColor)
	local b = Instance.new("TextButton")
	b.Size               = size
	b.Position           = pos
	b.BackgroundColor3   = bgColor or Color3.fromRGB(60,120,220)
	b.BorderSizePixel    = 0
	b.Text               = text
	b.TextColor3         = textColor or Color3.fromRGB(255,255,255)
	b.TextSize           = 15
	b.Font               = Enum.Font.GothamBold
	b.AutoButtonColor    = true
	b.Parent             = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	return b
end

-- ─── Уведомление──────────────────────────────────────────────────────────

local function buildNotifGui(screenGui)
	local frame = makeFrame(screenGui,
		UDim2.new(0, 340, 0, 50),
		UDim2.new(0.5, -170, 0, 10),
		Color3.fromRGB(20,20,20),0.1, "NotifFrame")
	frame.ZIndex = 10
	frame.Visible = false
	local lbl = makeLabel(frame, "",
		UDim2.new(1,-10,1,0),
		UDim2.new(0,5,0,0),
		Color3.fromRGB(255,255,255), 15, Enum.Font.GothamMedium)
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.ZIndex = 11
	notifLabel = lbl
	return frame
end

local notifFrame
local notifThread

function HudManager.ShowNotification(text, color)
	if notifLabel then
		notifLabel.Text      = text
		notifLabel.TextColor3 = color or Color3.fromRGB(255,255,255)
		notifFrame.Visible   = true
		if notifThread then task.cancel(notifThread) end
		notifThread = task.delay(4, function()
			if notifFrame then notifFrame.Visible = false end
		end)
	end
end

-- ─── Список целей ─────────────────────────────────────────────────────────

local function refreshTargets()
	if not targetListFrame then return end
	-- Чистим старые кнопки
	for _, ch in ipairs(targetListFrame:GetChildren()) do
		if ch:IsA("TextButton") or ch:IsA("Frame") then ch:Destroy() end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		if p == player then continue end

		local row = Instance.new("Frame")
		row.Size             = UDim2.new(1, -8, 0, 36)
		row.BackgroundColor3 = Color3.fromRGB(50,50,60)
		row.BackgroundTransparency = 0.2
		row.BorderSizePixel  = 0
		row.Parent           = targetListFrame
		local rc = Instance.new("UICorner")
		rc.CornerRadius = UDim.new(0,6)
		rc.Parent = row

		local nameLbl = makeLabel(row, p.Name,
			UDim2.new(0.55,0,1,0), UDim2.new(0,6,0,0),
			Color3.fromRGB(255,255,255), 14)

		local attackBtn = makeButton(row, "🚀 Атака",
			UDim2.new(0.42,0,0.75,0),
			UDim2.new(0.56,0,0.12,0),
			Color3.fromRGB(200,60,60))

		-- Определяем plotId цели
		attackBtn.MouseButton1Click:Connect(function()
			-- Ищем участок этого игрока по имени папки в Workspace
			local targetPlotId = nil
			for _, folder in ipairs(workspace:GetChildren()) do
				if folder.Name:match("^Plot_") then
					local sign = folder:FindFirstChild("Sign")
					if sign then
						local bb = sign:FindFirstChildOfClass("BillboardGui")
						if bb then
							local lbl2 = bb:FindFirstChildOfClass("TextLabel")
							if lbl2 and lbl2.Text == p.Name then
								targetPlotId = tonumber(folder.Name:match("%d+"))
							end
						end
					end
				end
			end
			if targetPlotId then
				Remotes.Get("LaunchRocket"):FireServer(targetPlotId)
			else
				HudManager.ShowNotification("Участок " .. p.Name .. " не найден!",
					Color3.fromRGB(200,200,60))
			end
		end)
	end
end

-- ─── Настройки ────────────────────────────────────────────────────────────

local settingsPanel
local animToggleBtn

local function buildSettings(screenGui)
	settingsPanel = makeFrame(screenGui,
		UDim2.new(0, 260, 0, 130),
		UDim2.new(0.5,-130,0.5,-65),
		Color3.fromRGB(20,20,30), 0.05, "SettingsPanel")
	settingsPanel.Visible = false
	settingsPanel.ZIndex  = 20

	makeLabel(settingsPanel, "⚙️ Настройки",
		UDim2.new(1,-10,0,30), UDim2.new(0,6,0,4),
		Color3.fromRGB(255,220,50), 18, Enum.Font.GothamBold)

	local animLabel = makeLabel(settingsPanel, "Анимация ракеты:",
		UDim2.new(0,150,0,26), UDim2.new(0,10,0,44),
		Color3.fromRGB(220,220,220), 14)

	animToggleBtn = makeButton(settingsPanel,
		animEnabled and "✅ Включена" or "❌ Выключена",
		UDim2.new(0,110,0,28),
		UDim2.new(0,148,0,42),
		animEnabled and Color3.fromRGB(40,160,60) or Color3.fromRGB(160,40,40))

	animToggleBtn.MouseButton1Click:Connect(function()
		animEnabled = not animEnabled
		animToggleBtn.Text = animEnabled and "✅ Включена" or "❌ Выключена"
		animToggleBtn.BackgroundColor3 =
			animEnabled and Color3.fromRGB(40,160,60) or Color3.fromRGB(160,40,40)
		Remotes.Get("SetAnimSetting"):FireServer(animEnabled)
	end)

	local hintLabel = makeLabel(settingsPanel,
		"💡 ЛКМ во время полёта — пропустить",
		UDim2.new(1,-10,0,20), UDim2.new(0,6,0,80),
		Color3.fromRGB(160,160,180), 12)

	local closeBtn = makeButton(settingsPanel, "✕",
		UDim2.new(0,26,0,26), UDim2.new(1,-32,0,4),
		Color3.fromRGB(160,50,50))
	closeBtn.MouseButton1Click:Connect(function()
		settingsPanel.Visible = false
	end)
end

-- ─── Главный HUD ──────────────────────────────────────────────────────────

function HudManager.Init(initAnimEnabled)
	animEnabled = initAnimEnabled ~= false

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name         = "TycoonHud"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	screenGui.Parent       = playerGui

	-- Уведомление (вверху по центру)
	notifFrame = buildNotifGui(screenGui)

	-- ── Панель ресурсов (верхний левый угол) ──
	local resPanel = makeFrame(screenGui,
		UDim2.new(0, 220, 0, 100),
		UDim2.new(0, 10, 0, 70),
		Color3.fromRGB(20,20,30), 0.1, "ResPanel")

	local gameTitle = makeLabel(resPanel, "🏭 Rocket Tycoon",
		UDim2.new(1,-10,0,24), UDim2.new(0,6,0,4),
		Color3.fromRGB(255,220,50), 17, Enum.Font.GothamBold)

	moneyLabel = makeLabel(resPanel, "💰 Деньги: 0",
		UDim2.new(1,-10,0,22), UDim2.new(0,6,0,30),
		Color3.fromRGB(255,220,50), 15)

	rocketLabel = makeLabel(resPanel, "🚀 Ракеты: 0",
		UDim2.new(1,-10,0,22), UDim2.new(0,6,0,54),
		Color3.fromRGB(255,120,80), 15)

	-- ── Кнопки действий──
	local actPanel = makeFrame(screenGui,
		UDim2.new(0, 220, 0, 100),
		UDim2.new(0, 10, 0, 178),
		Color3.fromRGB(20,20,30), 0.1, "ActPanel")

	upgradeBtn = makeButton(actPanel, "⬆️ Улучшить ферму",
		UDim2.new(1,-16,0,36),
		UDim2.new(0,8,0,8),
		Color3.fromRGB(60,160,80))
	upgradeBtn.MouseButton1Click:Connect(function()
		Remotes.Get("UpgradeFarm"):FireServer()
	end)

	buyRocketBtn = makeButton(actPanel,
		"🛒 Купить ракету (" .. Config.ROCKET_COST .. ")",
		UDim2.new(1,-16,0,36),
		UDim2.new(0,8,0,52),
		Color3.fromRGB(180,80,200))
	buyRocketBtn.MouseButton1Click:Connect(function()
		Remotes.Get("BuyRocket"):FireServer()
	end)

	-- ── Список целей ──
	local targetPanel = makeFrame(screenGui,
		UDim2.new(0, 220, 0, 250),
		UDim2.new(1, -230, 0, 70),
		Color3.fromRGB(20,20,30), 0.1, "TargetPanel")

	makeLabel(targetPanel, "🎯 Цели для атаки",
		UDim2.new(1,-10,0,24), UDim2.new(0,6,0,4),
		Color3.fromRGB(255,120,80), 16, Enum.Font.GothamBold)

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Size             = UDim2.new(1,-8,1,-36)
	scrollFrame.Position         = UDim2.new(0,4,0,32)
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel  = 0
	scrollFrame.ScrollBarThickness = 4
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(120,120,140)
	scrollFrame.CanvasSize       = UDim2.new(0,0,0,0)
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.Parent           = targetPanel

	local layout = Instance.new("UIListLayout")
	layout.SortOrder= Enum.SortOrder.LayoutOrder
	layout.Padding= UDim.new(0,4)
	layout.Parent     = scrollFrame

	targetListFrame = scrollFrame

	-- Обновляем список при изменении игроков
	Players.PlayerAdded:Connect(function() task.wait(0.5) refreshTargets() end)
	Players.PlayerRemoving:Connect(function() task.wait(0.5) refreshTargets() end)
	task.delay(3, refreshTargets)

	-- ── Кнопка настроек ──
	local settingsBtn = makeButton(screenGui, "⚙️",
		UDim2.new(0,40,0,40),
		UDim2.new(1,-52,0,10),
		Color3.fromRGB(60,60,80))
	settingsBtn.TextSize = 20
	settingsBtn.MouseButton1Click:Connect(function()
		settingsPanel.Visible = not settingsPanel.Visible
	end)

	buildSettings(screenGui)
end

function HudManager.UpdateData(data)
	if moneyLabel  then moneyLabel.Text  = "💰 Деньги:" .. (data.money or 0) end
	if rocketLabel then rocketLabel.Text = "🚀 Ракеты: " .. (data.rockets or 0) end
	if data.animEnabled ~= nil then
		animEnabled = data.animEnabled
		if animToggleBtn then
			animToggleBtn.Text = animEnabled and "✅ Включена" or "❌ Выключена"
			animToggleBtn.BackgroundColor3 =
				animEnabled and Color3.fromRGB(40,160,60) or Color3.fromRGB(160,40,40)
		end
	end
	-- Обновить список целей
	refreshTargets()
end

function HudManager.IsAnimEnabled()
	return animEnabled
end

return HudManager