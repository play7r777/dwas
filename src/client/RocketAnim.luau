-- RocketAnim.luau — анимация полёта ракеты с дугой, взрывом и пропуском поЛКМ
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Debris           = game:GetService("Debris")
local Config           = require(game.ReplicatedStorage.Shared.Config)

local RocketAnim = {}

-- Создаёт эффект взрыва в точке
local function spawnExplosion(pos)
	-- Основная сфера взрыва
	local ball = Instance.new("Part")
	ball.Shape= Enum.PartType.Ball
	ball.Size     = Vector3.new(1, 1, 1)
	ball.Position = pos
	ball.Anchored = true
	ball.CanCollide = false
	ball.CastShadow = false
	ball.Material = Enum.Material.Neon
	ball.Color= Color3.fromRGB(255, 160, 30)
	ball.Parent= workspace

	-- Анимация расширения взрыва
	local tween = TweenService:Create(ball,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(14, 14, 14), Transparency = 1 })
	tween:Play()
	Debris:AddItem(ball, 0.5)

	-- Кольцо взрыва
	local ring = Instance.new("Part")
	ring.Shape      = Enum.PartType.Cylinder
	ring.Size       = Vector3.new(0.4, 2, 2)
	ring.Position   = pos
	ring.Anchored   = true
	ring.CanCollide = false
	ring.CastShadow = false
	ring.Material   = Enum.Material.Neon
	ring.Color= Color3.fromRGB(255, 80, 20)
	ring.Orientation = Vector3.new(0, 0, 90)
	ring.Parent      = workspace

	local ringTween = TweenService:Create(ring,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.4, 20, 20), Transparency = 1 })
	ringTween:Play()
	Debris:AddItem(ring, 0.6)

	-- Дым
	for i = 1, 6 do
		task.spawn(function()
			local smoke = Instance.new("Part")
			smoke.Shape   = Enum.PartType.Ball
			smoke.Size    = Vector3.new(2, 2, 2)
			smoke.Position= pos + Vector3.new(
				(math.random() - 0.5) * 8,
				math.random() * 4,
				(math.random() - 0.5) * 8
			)
			smoke.Anchored= true
			smoke.CanCollide = false
			smoke.CastShadow = false
			smoke.Material= Enum.Material.SmoothPlastic
			smoke.Color   = Color3.fromRGB(80+ math.random(40), 80 + math.random(40), 80 + math.random(40))
			smoke.Parent  = workspace
			local st = TweenService:Create(smoke,
				TweenInfo.new(0.8, Enum.EasingStyle.Quad),
				{ Size = Vector3.new(6,6,6), Transparency = 1,
				  Position = smoke.Position + Vector3.new(0,6, 0) })
			st:Play()
			Debris:AddItem(smoke, 1)
		end)
	end
end

-- Вычисляет позицию на дуге (0..1)
local function arcPos(origin, target, t)
	local arc = Config.ROCKET_ARC
	local straight = origin:Lerp(target, t)
	local height= math.sin(t * math.pi) * arc
	return Vector3.new(straight.X, straight.Y + height, straight.Z)
end

--[[
	Play(data, animEnabled)
	data = { shooterName, originPos, targetPos, targetPlotId, destroyed }
	animEnabled = bool
]]
function RocketAnim.Play(data, animEnabled)
	local origin = data.originPos
	local target = data.targetPos

	-- Если анимация выключена — сразу взрыв
	if not animEnabled then
		spawnExplosion(target)
		return
	end

	-- Создаёмракету
	local rocket = Instance.new("Part")
	rocket.Name= "Rocket"
	rocket.Size     = Vector3.new(0.6, 0.6, 2.5)
	rocket.Position = origin
	rocket.Anchored = true
	rocket.CanCollide = false
	rocket.CastShadow = false
	rocket.Material = Enum.Material.Neon
	rocket.Color    = Color3.fromRGB(255, 60, 60)
	rocket.Parent   = workspace

	-- Огненный хвост
	local trail = Instance.new("PointLight")
	trail.Brightness = 5
	trail.Range= 14
	trail.Color= Color3.fromRGB(255, 140, 30)
	trail.Parent= rocket

	-- Управление пропуском — нажатие ЛКМ
	local skipped = false
	local skipConn
	skipConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			skipped = true
		end
	end)

	-- Длительность зависит от расстояния
	local dist= (target - origin).Magnitude
	local duration = math.clamp(dist / Config.ROCKET_SPEED, 0.6, Config.ROCKET_ANIM_TIME)
	local steps    = math.ceil(duration / 0.03)

	for i = 1, steps do
		if skipped then break end
		local t = i / steps
		local pos = arcPos(origin, target, t)

		-- Ориентируем ракету по направлению движения
		local nextT= math.min(t + 0.05, 1)
		local nextPos = arcPos(origin, target, nextT)
		local dir= (nextPos - pos)
		if dir.Magnitude > 0.001 then
			rocket.CFrame = CFrame.lookAt(pos, pos + dir)
		end

		task.wait(0.03)
	end

	-- Убираем ракету и показываем взрыв
	skipConn:Disconnect()
	rocket:Destroy()
	spawnExplosion(target)

	-- Сообщение о результате
	local msg
	if data.destroyed then
		msg = "💥 " .. data.shooterName .. " уничтожил ферму!"
	else
		msg = "🚀 " .. data.shooterName .. " атаковал участок " .. (data.targetPlotId or "?")
	end
	-- Показываем через require, чтобы не создавать circular dependency
	local ok, HudManager = pcall(require, script.Parent.HudManager)
	if ok and HudManager then
		HudManager.ShowNotification(msg,
			data.destroyed and Color3.fromRGB(220,80,80) or Color3.fromRGB(255,180,50))
	end
end

return RocketAnim