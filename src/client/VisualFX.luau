-- VisualFX.luau — Визуальные 3D эффекты: всплывающие деньги +$Cash над зданиями
local TweenService = game:GetService("TweenService")
local Debris       = game:GetService("Debris")

local VisualFX = {}

function VisualFX.SpawnIncome(pos, amount)
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Position = pos
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 120, 0, 40)
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = true
	bb.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "+$" .. amount
	label.TextColor3 = Color3.fromRGB(60, 255, 100)
	label.TextStrokeColor3 = Color3.fromRGB(0, 50, 0)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = bb

	-- Анимация взлета вверх и растворения
	local tweenInfo = TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local moveTween = TweenService:Create(part, tweenInfo, { Position = pos + Vector3.new(0, 8, 0) })
	local fadeTween = TweenService:Create(label, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })

	moveTween:Play()
	fadeTween:Play()

	Debris:AddItem(part, 1.5)
end

return VisualFX
